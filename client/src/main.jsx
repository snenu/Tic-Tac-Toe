import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';
import { LineraContextProvider } from './context/LineraContext';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <BrowserRouter>
      <LineraContextProvider>
        <App />
      </LineraContextProvider>
    </BrowserRouter>
  </React.StrictMode>
);
