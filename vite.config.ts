import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'node:url'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      // postcss (via marpit) imports node built-ins it never calls at render time
      path: fileURLToPath(new URL('./src/shims/empty.ts', import.meta.url)),
      fs: fileURLToPath(new URL('./src/shims/empty.ts', import.meta.url)),
      url: fileURLToPath(new URL('./src/shims/empty.ts', import.meta.url)),
      'source-map-js': fileURLToPath(new URL('./src/shims/empty.ts', import.meta.url)),
    },
  },
  worker: { format: 'es' },
  test: { environment: 'node', include: ['src/**/*.test.ts'] },
} as any)
