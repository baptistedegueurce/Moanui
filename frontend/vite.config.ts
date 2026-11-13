import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// En développement, l'API Python tourne sur 8765 ; en production elle sert elle-même ces fichiers.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: '../backend/moanui/static',
    emptyOutDir: true,
    chunkSizeWarningLimit: 4000,
  },
  server: {
    port: 5173,
    proxy: { '/api': 'http://127.0.0.1:8765' },
  },
});
