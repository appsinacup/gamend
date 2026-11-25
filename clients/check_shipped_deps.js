#!/usr/bin/env node
/**
 * check_shipped_deps.js
 *
 * Fail the build when the published bundle requires a package that the
 * published package.json does not declare.
 *
 * The handcrafted realtime code reaches protobufjs through
 * realtime.js -> gamend_proto.js -> gamend_realtime.pb.js. Every generated API
 * class imports fine without it, so the build and the smoke checks stay green
 * while `require('@ughuuu/gamend')` throws "Cannot find module
 * 'protobufjs/minimal.js'" on a clean install of a package that does not
 * declare it.
 *
 *   node clients/check_shipped_deps.js
 */

const fs = require('fs')
const path = require('path')
const { builtinModules } = require('module')

const pkgDir = path.join(__dirname, 'javascript')
const distDir = path.join(pkgDir, 'dist')
const pkg = JSON.parse(fs.readFileSync(path.join(pkgDir, 'package.json'), 'utf8'))

const declared = new Set([
  ...Object.keys(pkg.dependencies || {}),
  ...Object.keys(pkg.peerDependencies || {}),
  ...Object.keys(pkg.optionalDependencies || {}),
])
const builtins = new Set(builtinModules)

/** "protobufjs/minimal.js" -> "protobufjs"; "@scope/n/sub" -> "@scope/n" */
function packageName (specifier) {
  const parts = specifier.split('/')
  return specifier.startsWith('@') ? parts.slice(0, 2).join('/') : parts[0]
}

function* jsFiles (dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) yield* jsFiles(full)
    else if (entry.name.endsWith('.js')) yield full
  }
}

if (!fs.existsSync(distDir)) {
  console.error(`check_shipped_deps: ${distDir} does not exist - build first`)
  process.exit(1)
}

// Babel compiles every import down to require(), so scanning dist covers both.
const requireCall = /\brequire\(\s*['"]([^'"]+)['"]\s*\)/g
const missing = new Map()

for (const file of jsFiles(distDir)) {
  const source = fs.readFileSync(file, 'utf8')
  for (const [, specifier] of source.matchAll(requireCall)) {
    if (specifier.startsWith('.') || specifier.startsWith('/')) continue
    const name = packageName(specifier)
    if (builtins.has(name) || name.startsWith('node:')) continue
    if (declared.has(name)) continue
    if (!missing.has(name)) missing.set(name, new Set())
    missing.get(name).add(path.relative(pkgDir, file))
  }
}

if (missing.size === 0) {
  console.log(`check_shipped_deps: OK - every module the bundle requires is declared (${declared.size} deps)`)
  process.exit(0)
}

console.error('check_shipped_deps: the bundle requires packages that are not declared:\n')
for (const [name, files] of missing) {
  const shown = [...files].slice(0, 3).join(', ')
  const more = files.size > 3 ? ` (+${files.size - 3} more)` : ''
  console.error(`  ${name}  <- ${shown}${more}`)
}
console.error('\nInstalling the package would fail at require() time. Declare them and re-run.')
process.exit(1)
