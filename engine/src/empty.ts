// Stand-in for node built-ins that postcss references but never executes in the browser.
const noop = () => undefined
export default new Proxy({}, { get: () => noop })
export const isAbsolute = noop, resolve = noop, dirname = noop, relative = noop, join = noop, sep = '/'
export const existsSync = noop, readFileSync = noop, realpathSync = noop
export const fileURLToPath = noop, pathToFileURL = noop
export const SourceMapConsumer = class {}, SourceMapGenerator = class {}
