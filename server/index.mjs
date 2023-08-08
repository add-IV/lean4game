import { WebSocketServer } from 'ws';
import express from 'express'
import path from 'path'
import * as cp from 'child_process';
import * as url from 'url';
import * as rpc from 'vscode-ws-jsonrpc';
import * as jsonrpcserver from 'vscode-ws-jsonrpc/server';
import os from 'os';
import anonymize from 'ip-anonymize';
import { importTrigger, importStatus } from './import.mjs'

/** Preloaded games. The keys refer to the docker tags of the virtual machines.
 * The number `queueLength` determines how many instances of the docker container
 * get started before any user shows up to have them up and running immediately.
 * The values `name`, `module`, and `dir` are just used for development where we
 * use a project directory instead of a docker container.
*/
const games = {
    "g/add/addgame": { // the tag of our docker image
        // module: "Game",  // The lean module's name. Defaults to "Game"
        // name: "Adam",    // For the `Game "Adam"` tag in the games. Defaults to "MyGame"
        dir: "../../../../Add", // only for development, ignore
        queueLength: 5
    }
}
// Note: If `module` and `name` are uncommented, one also needs to add them as arguments to
// the `--server` call below.

const __filename = url.fileURLToPath(import.meta.url);
const __dirname = url.fileURLToPath(new URL('.', import.meta.url));

const app = express()

const PORT = process.env.PORT || 8080;

var router = express.Router();

router.get('/import/status/:owner/:repo', importStatus)
router.get('/import/trigger/:owner/:repo', importTrigger)

const server = app
  .use(express.static(path.join(__dirname, '../client/dist/')))
  .use('/', router)
  .listen(PORT, () => console.log(`Listening on ${PORT}`));

const wss = new WebSocketServer({ server })

var socketCounter = 0

const environment = process.env.NODE_ENV
const isDevelopment = environment === 'development'

/** We keep queues of started Lean Server processes to be ready when a user arrives */
const queue = {}

function startServerProcess(tag) {
    let serverProcess
    if (isDevelopment && games[tag]?.dir) {
        serverProcess = cp.spawn("./gameserver",
            ["--server", games[tag].dir], // games[tag].module, games[tag].name
            { cwd: "./build/bin/" })
    } else {
        serverProcess =  cp.spawn("docker",
            ["run", "--runtime=runsc", "--network=none", "--rm", "-i", `${tag}`],
            { cwd: "." })
    }
    serverProcess.on('error', error =>
        console.error(`Launching Lean Server failed: ${error}`)
    );
    if (serverProcess.stderr !== null) {
        serverProcess.stderr.on('data', data =>
            console.error(`Lean Server: ${data}`)
        );
    }
    return serverProcess
}

/** start Lean Server processes to refill the queue */
function fillQueue(tag) {
    while (queue[tag].length < games[tag].queueLength) {
        const serverProcess = startServerProcess(tag)
        queue[tag].push(serverProcess)
    }
}

if (!isDevelopment) { // Don't use queue in development
    for (let tag in games) {
        queue[tag] = []
        fillQueue(tag)
    }
}

const urlRegEx = /^\/websocket\/g\/([\w.-]+)\/([\w.-]+)$/ // matches /websocket/g/first/second ; first and second are grousp; in our case add and addgame

wss.addListener("connection", function(ws, req) {
    const reRes = urlRegEx.exec(req.url)
    if (!reRes) { console.error(`Connection refused because of invalid URL: ${req.url}`); return; }
    const owner = reRes[1]
    const repo = reRes[2]
    const tag = `g/${owner.toLowerCase()}/${repo.toLowerCase()}` // g/add/addgame

    let ps;
    if (!queue[tag] || queue[tag].length == 0) {
        ps = startServerProcess(tag)
    } else {
        ps = queue[tag].shift() // Pick the first Lean process; it's likely to be ready immediately
        fillQueue(tag)
    }

    socketCounter += 1;
    const ip = anonymize(req.headers['x-forwarded-for'] || req.socket.remoteAddress)
    console.log(`[${new Date()}] Socket opened - ${ip}`)

    const socket = {
        onMessage: (cb) => { ws.on("message", cb) },
        onError: (cb) => { ws.on("error", cb) },
        onClose: (cb) => { ws.on("close", cb) },
        send: (data, cb) => { ws.send(data,cb) }
    }
    const reader = new rpc.WebSocketMessageReader(socket);
    const writer = new rpc.WebSocketMessageWriter(socket);
    const socketConnection = jsonrpcserver.createConnection(reader, writer, () => ws.close())
    const serverConnection = jsonrpcserver.createProcessStreamConnection(ps);
    socketConnection.forward(serverConnection, message => {
        if (isDevelopment) {console.log(`CLIENT: ${JSON.stringify(message)}`)}
        return message;
    });
    serverConnection.forward(socketConnection, message => {
      if (isDevelopment) {console.log(`SERVER: ${JSON.stringify(message)}`)}
        return message;
    });

    console.log(`[${new Date()}] Number of open sockets - ${socketCounter}`)
    console.log(`[${new Date()}] Free RAM - ${Math.round(os.freemem() / 1024 / 1024)} / ${Math.round(os.totalmem() / 1024 / 1024)} MB`)

    ws.on('close', () => {
      console.log(`[${new Date()}] Socket closed - ${ip}`)
      socketCounter -= 1;
    })

    socketConnection.onClose(() => serverConnection.dispose());
    serverConnection.onClose(() => socketConnection.dispose());
})
