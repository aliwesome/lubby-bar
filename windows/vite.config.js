import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// Tauri serves the built `dist/`. Fixed port + no clearing so the Rust side and
// the dev server agree.
export default defineConfig({
    plugins: [react()],
    clearScreen: false,
    server: { port: 5173, strictPort: true },
    build: { target: 'esnext', emptyOutDir: true },
});
