import { GameHint } from "./rpcApi";
import * as React from 'react';
import { Alert, FormControlLabel, Switch } from '@mui/material';
import Markdown from '../Markdown';

function Hint({hint} : {hint: GameHint}) {
  return <div className="message info"><Markdown>{hint.text}</Markdown></div>
}

export function Hints({hints} : {hints: GameHint[]}) {


  const [showHints, setShowHints] = React.useState(false);

  const openHints = hints.filter(hint => !hint.hidden)
  const hiddenHints = hints.filter(hint => hint.hidden)

  return <>
    {openHints.map(hint => <Hint hint={hint} />)}
    {hiddenHints.length > 0 &&
        <FormControlLabel
          control={<Switch checked={showHints} onChange={() => setShowHints((prev) => !prev)} />}
          label="I need help!"
        />}
    {showHints && hiddenHints.map(hint => <Hint hint={hint} />)}
  </>
}
