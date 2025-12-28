import { defineConfig } from 'vite';
import { resolve } from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/iife.ts'),
      name: 'arborium',
      formats: ['iife'],
      fileName: () => 'arborium.iife.js',
    },
    outDir: 'dist',
    emptyOutDir: false, // Don't clear dist (ESM build runs first)
    target: 'es2022',
    minify: 'esbuild',
    sourcemap: true,
  },
});
