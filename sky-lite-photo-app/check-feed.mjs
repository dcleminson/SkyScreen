import fs from 'node:fs/promises'
import path from 'node:path'

const inputPath = process.argv[2] ?? 'public/photos-from-drive.json'
const outputPath = process.argv[3] ?? 'public/photos-from-drive.filtered.json'
const timeoutMs = 10000

const absoluteInput = path.resolve(process.cwd(), inputPath)
const absoluteOutput = path.resolve(process.cwd(), outputPath)

const text = await fs.readFile(absoluteInput, 'utf8')
const body = JSON.parse(text)
const images = Array.isArray(body.images) ? body.images : []

if (images.length === 0) {
  console.log(`No images found in ${inputPath}`)
  process.exit(0)
}

const allowedExt = /\.(jpg|jpeg|png|webp|gif|bmp|heic|heif|dng)$/i

async function checkImage(image) {
  const name = typeof image.name === 'string' ? image.name : 'unnamed'
  const url = typeof image.url === 'string' ? image.url : ''

  if (!url) {
    return { ok: false, reason: 'missing-url', name, url }
  }

  const extAllowed = allowedExt.test(name) || allowedExt.test(url)
  if (!extAllowed) {
    return { ok: false, reason: 'unsupported-extension', name, url }
  }

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)

  try {
    let response = await fetch(url, {
      method: 'HEAD',
      signal: controller.signal,
      redirect: 'follow',
    })
    if (!response.ok || response.status >= 400) {
      response = await fetch(url, {
        method: 'GET',
        headers: { Range: 'bytes=0-0' },
        signal: controller.signal,
        redirect: 'follow',
      })
    }
    const contentType = response.headers.get('content-type') ?? ''
    const okType = contentType.startsWith('image/') || contentType === ''
    const ok = response.ok && response.status < 400 && okType
    return { ok, status: response.status, contentType, name, url }
  } catch (error) {
    return {
      ok: false,
      reason: error instanceof Error ? error.message : 'request-failed',
      name,
      url,
    }
  } finally {
    clearTimeout(timer)
  }
}

const results = await Promise.all(images.map(checkImage))
const passed = results.filter((item) => item.ok)
const failed = results.filter((item) => !item.ok)

const filtered = {
  images: passed.map(({ name, url }) => ({ name, url })),
}

await fs.writeFile(absoluteOutput, `${JSON.stringify(filtered, null, 2)}\n`, 'utf8')

console.log(`Checked ${results.length} images.`)
console.log(`Passed: ${passed.length}`)
console.log(`Failed: ${failed.length}`)
console.log(`Filtered feed written to: ${outputPath}`)

if (failed.length > 0) {
  console.log('\nFailed entries:')
  for (const item of failed) {
    const why = item.reason ?? `status=${item.status} type=${item.contentType ?? ''}`
    console.log(`- ${item.name}: ${why}`)
  }
}
