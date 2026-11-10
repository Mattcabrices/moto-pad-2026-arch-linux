import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
// npm run dev: the API calls go to the Node app on port 3000.
export default defineConfig({ plugins: [react()], server: { proxy: { '/api': 'http://127.0.0.1:3000' } } });
