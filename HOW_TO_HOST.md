# How to host this project

## 1. Install needed software

needed software:

- docker
- gVisor
- npm + node + pm2
- whatever you use for a reverse proxy

## 2. Use docker to build the image

1. clone the [repo](https://github.com/hegl-lab/addgame)
2. cd into the repo
3. run `docker build . --file Dockerfile --tag g/add/addgame` (tag is important)
4. you can delete the repo now if you want

## 3. Use pm2 to start the server

1. clone the server repo (this one)
2. cd into the repo
3. you might have to run `npm install` and `npm run build` first, but since the project uses webpack and i have included the bundle.js files it might not be necessary
4. start pm2

```bash
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

if you want to change the port the server runs on, you can do so in the ecosystem.config.js file

## 4. Use your favorite reverse proxy to redirect traffic to the server

I use nginx, here is part of my config:

```nginx
server {
  server_name  add-iv.com;

  location / {
    proxy_pass      http://localhost:8002/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }

  listen [::]:443 ssl ipv6only=on; # managed by Certbot
  listen 443 ssl; # managed by Certbot
  ssl_certificate /etc/letsencrypt/live/add-iv.com/fullchain.pem; # managed by Certbot
  ssl_certificate_key /etc/letsencrypt/live/add-iv.com/privkey.pem; # managed by Certbot
  include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

}

server {
  if ($host = add-iv.com) {
    return 301 https://$host$request_uri;
  } # managed by Certbot
    listen       80 default_server;
    listen       [::]:80 default_server;
    server_name  add-iv.com;
  return 404; # managed by Certbot
}
```
