import * as React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { ConnectionContext, connection } from './connection'
import { store } from './state/store';
import { Provider } from 'react-redux';
import {
  createHashRouter,
  RouterProvider,
  Route,
} from "react-router-dom";
import ErrorPage from './ErrorPage';
import Welcome from './components/Welcome';
import LandingPage from './components/LandingPage';
import Level from './components/Level';
import { monacoSetup } from 'lean4web/client/src/monacoSetup';
import { redirect } from 'react-router-dom';

monacoSetup()

const router = createHashRouter([
  {
    path: "/g/:owner/:repo",
    element: <App />,
    errorElement: <ErrorPage />,
    children: [
      {
        path: "/g/:owner/:repo",
        element: <Welcome />,
      },
      {
        path: "/g/:owner/:repo/world/:worldId/level/:levelId",
        element: <Level />,
      },
    ],
  },
]);

const container = document.getElementById('root');
const root = createRoot(container!);
root.render(
  <React.StrictMode>
    <Provider store={store}>
      <ConnectionContext.Provider value={connection}>
        <RouterProvider router={router} />
      </ConnectionContext.Provider>
    </Provider>
  </React.StrictMode>
);
