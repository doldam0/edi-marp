import { defineConfig } from 'vite'
import { fileURLToPath } from 'node:url'

const shim = fileURLToPath(new URL('./src/empty.ts', import.meta.url))

// Builds a single self-contained IIFE (`window.EdiEngine`) that the macOS app
// loads into a hidden WKWebView. No network access is ever required.
export default defineConfig({
  resolve: {
    // postcss (via marpit) imports node built-ins it never calls at render time
    alias: { path: shim, fs: shim, url: shim, 'source-map-js': shim },
  },
  define: { 'process.env.NODE_ENV': '"production"' },
  build: {
    lib: { entry: 'src/index.ts', name: 'EdiEngine', formats: ['iife'], fileName: () => 'engine.js' },
    // Override to the built app's Resources folder for live reload:
    //   EDIMARP_OUT_DIR=<App>.app/Contents/Resources npm run watch
    outDir: process.env.EDIMARP_OUT_DIR || '../EdiMarp/Resources/Web',
    emptyOutDir: false,
    sourcemap: false,
    minify: true,
    target: 'safari17',
    rollupOptions: { output: { inlineDynamicImports: true } },
  },
})
