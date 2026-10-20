<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'

function readIntSetting(key, fallback, min, max) {
  const raw = localStorage.getItem(key)
  if (raw === null) return fallback
  const parsed = Number.parseInt(raw, 10)
  if (Number.isNaN(parsed)) return fallback
  const lowerBounded = Math.max(min, parsed)
  return typeof max === 'number' ? Math.min(max, lowerBounded) : lowerBounded
}

function readBoolSetting(key, fallback) {
  const raw = localStorage.getItem(key)
  if (raw === null) return fallback
  return raw === 'true'
}

const slides = ref([])
const currentIndex = ref(0)
const intervalSeconds = ref(readIntSetting('slideshowIntervalSeconds', 5, 1, 600))
const isPlaying = ref(false)
const shuffleEnabled = ref(readBoolSetting('slideshowShuffleEnabled', false))
const transitionMs = ref(readIntSetting('slideshowTransitionMs', 450, 100, 8000))
const statusMessage = ref('Load images to start your slideshow.')
const driveStatus = ref('Connect Google Drive to import photos.')

const clientId = ref(localStorage.getItem('googleClientId') ?? '')
const folderId = ref(localStorage.getItem('googleFolderId') ?? '')
const importLimit = ref(
  Number.parseInt(localStorage.getItem('googleImportLimit') ?? '10', 10),
)
const isGisReady = ref(false)
const isAuthorized = ref(false)
const isDriveBusy = ref(false)
const accessToken = ref('')
const gisAttempts = ref(0)
const showExitHelp = ref(false)
const orientationLabel = ref('Unknown')
const publicFeedUrl = ref(
  localStorage.getItem('publicFeedUrl') ?? '/photos.json',
)
const publicFeedStatus = ref('Load a public image feed URL to skip Google OAuth.')
const publicFeedClicks = ref(0)

const presentationMode = ref(false)
const controlsVisible = ref(true)
const slideProgressMs = ref(0)
const feedEditorText = ref('')

let slideshowTimer = null
let progressTimer = null
let controlHideTimer = null
let slideStartedAtMs = 0
let tokenClient = null
let orientationTimer = null
let touchStartX = 0
let touchStartY = 0
let touchMoved = false
let swipeConsumedTap = false

const hasSlides = computed(() => slides.value.length > 0)
const currentSlide = computed(() => slides.value[currentIndex.value] ?? null)
const canAuthorizeDrive = computed(
  () => isGisReady.value && clientId.value.trim().length > 0,
)
const intervalMs = computed(() => Math.max(1, intervalSeconds.value) * 1000)
const progressPercent = computed(() =>
  Math.min(100, Math.round((slideProgressMs.value / intervalMs.value) * 100)),
)
const slideCounterLabel = computed(() => {
  if (!hasSlides.value) return '0 / 0'
  return `${currentIndex.value + 1} / ${slides.value.length}`
})

function saveDriveSettings() {
  localStorage.setItem('googleClientId', clientId.value.trim())
  localStorage.setItem('googleFolderId', folderId.value.trim())
  localStorage.setItem('googleImportLimit', String(Math.max(1, importLimit.value)))
}

function savePublicFeedSettings() {
  localStorage.setItem('publicFeedUrl', publicFeedUrl.value.trim())
}

function extractDriveFolderId(value) {
  const trimmed = value.trim()
  if (!trimmed) return ''

  const directIdMatch = trimmed.match(/^[a-zA-Z0-9_-]{10,}$/)
  if (directIdMatch) return trimmed

  try {
    const url = new URL(trimmed)
    const byPath = url.pathname.match(/\/folders\/([a-zA-Z0-9_-]+)/)
    if (byPath?.[1]) return byPath[1]
    const byQuery = url.searchParams.get('id')
    if (byQuery) return byQuery
  } catch {
    return ''
  }

  return ''
}

function normalizeHttpUrl(value) {
  const trimmed = value.trim()
  if (!trimmed) return ''
  if (trimmed.startsWith('/')) return trimmed

  if (/^https?:\/\//i.test(trimmed)) {
    try {
      const parsed = new URL(trimmed)
      if (parsed.host === window.location.host) {
        return `${parsed.pathname}${parsed.search}`
      }
    } catch {
      return trimmed
    }
    return trimmed
  }

  if (/^[\w.-]+(:\d+)?(\/.*)?$/.test(trimmed)) return `http://${trimmed}`
  return trimmed
}

function revokeSlideUrls(slideList) {
  slideList.forEach((slide) => {
    if (slide.revocable) URL.revokeObjectURL(slide.url)
  })
}

function resetProgress() {
  slideStartedAtMs = Date.now()
  slideProgressMs.value = 0
}

function stopProgressTicker() {
  if (progressTimer !== null) {
    clearInterval(progressTimer)
    progressTimer = null
  }
}

function startProgressTicker() {
  stopProgressTicker()
  progressTimer = setInterval(() => {
    if (!isPlaying.value) return
    slideProgressMs.value = Math.min(intervalMs.value, Date.now() - slideStartedAtMs)
  }, 120)
}

function stopSlideshow() {
  if (slideshowTimer !== null) {
    clearInterval(slideshowTimer)
    slideshowTimer = null
  }
  stopProgressTicker()
  isPlaying.value = false
  slideProgressMs.value = 0
}

function pickRandomIndex(current, total) {
  if (total <= 1) return current
  let next = current
  while (next === current) {
    next = Math.floor(Math.random() * total)
  }
  return next
}

function nextSlide() {
  if (!hasSlides.value) return
  if (shuffleEnabled.value) {
    currentIndex.value = pickRandomIndex(currentIndex.value, slides.value.length)
  } else {
    currentIndex.value = (currentIndex.value + 1) % slides.value.length
  }
  resetProgress()
}

function previousSlide() {
  if (!hasSlides.value) return
  if (shuffleEnabled.value) {
    currentIndex.value = pickRandomIndex(currentIndex.value, slides.value.length)
  } else {
    currentIndex.value =
      (currentIndex.value - 1 + slides.value.length) % slides.value.length
  }
  resetProgress()
}

function startSlideshow() {
  if (!hasSlides.value) {
    statusMessage.value = 'Please upload at least one image first.'
    return
  }

  stopSlideshow()
  slideshowTimer = setInterval(nextSlide, intervalMs.value)
  resetProgress()
  startProgressTicker()
  isPlaying.value = true
  statusMessage.value = `Slideshow running every ${intervalSeconds.value} second${intervalSeconds.value === 1 ? '' : 's'}.`
}

function toggleSlideshow() {
  if (isPlaying.value) {
    stopSlideshow()
    statusMessage.value = 'Slideshow paused.'
    return
  }
  startSlideshow()
}

function clearSlides() {
  stopSlideshow()
  revokeSlideUrls(slides.value)
  slides.value = []
  currentIndex.value = 0
  statusMessage.value = 'All images cleared.'
}

function appendSlides(newSlides) {
  slides.value = [...slides.value, ...newSlides]
  if (slides.value.length > 0 && currentIndex.value >= slides.value.length) {
    currentIndex.value = 0
  }
}

function loadFiles(event) {
  const files = event.target.files ? Array.from(event.target.files) : []
  if (files.length === 0) return

  const imageFiles = files.filter((file) => file.type.startsWith('image/'))
  if (imageFiles.length === 0) {
    statusMessage.value = 'No image files were found in the selected files.'
    return
  }

  const localSlides = imageFiles.map((file) => ({
    name: file.name,
    url: URL.createObjectURL(file),
    revocable: true,
  }))

  clearSlides()
  appendSlides(localSlides)
  statusMessage.value = `Loaded ${localSlides.length} local image${localSlides.length === 1 ? '' : 's'}.`
}

async function toggleFullscreen() {
  if (!document.fullscreenElement) {
    await document.documentElement.requestFullscreen()
    return
  }
  await document.exitFullscreen()
}

function showHomeHelp() {
  showExitHelp.value = true
}

function tryExitApp() {
  showHomeHelp()
  if (document.fullscreenElement) {
    document.exitFullscreen().catch(() => {})
  }
  try {
    window.close()
  } catch {
    // Browser security often blocks window.close() for normal tabs.
  }
}

function reloadPage() {
  window.location.reload()
}

function updateOrientationLabel() {
  if (window.matchMedia?.('(orientation: landscape)').matches) {
    orientationLabel.value = 'Landscape'
    return
  }
  orientationLabel.value =
    window.innerWidth > window.innerHeight ? 'Landscape' : 'Portrait'
}

function scheduleAutoHideControls() {
  if (!presentationMode.value) return
  if (controlHideTimer !== null) clearTimeout(controlHideTimer)
  controlHideTimer = setTimeout(() => {
    controlsVisible.value = false
  }, 3500)
}

function setControlsVisible(value) {
  controlsVisible.value = value
  if (value) {
    scheduleAutoHideControls()
  } else if (controlHideTimer !== null) {
    clearTimeout(controlHideTimer)
    controlHideTimer = null
  }
}

function onViewerTouchStart(event) {
  const firstTouch = event.changedTouches?.[0]
  if (!firstTouch) return
  touchStartX = firstTouch.clientX
  touchStartY = firstTouch.clientY
  touchMoved = false
}

function onViewerTouchMove(event) {
  const firstTouch = event.changedTouches?.[0]
  if (!firstTouch) return
  const dx = Math.abs(firstTouch.clientX - touchStartX)
  const dy = Math.abs(firstTouch.clientY - touchStartY)
  touchMoved = dx > 14 || dy > 14
}

function onViewerTouchEnd(event) {
  if (!presentationMode.value || !hasSlides.value) return
  const firstTouch = event.changedTouches?.[0]
  if (!firstTouch) return

  const dx = firstTouch.clientX - touchStartX
  const dy = firstTouch.clientY - touchStartY
  const absX = Math.abs(dx)
  const absY = Math.abs(dy)

  if (absX < 36 || absX < absY * 1.2) return

  swipeConsumedTap = true
  if (dx < 0) {
    nextSlide()
  } else {
    previousSlide()
  }
}

async function enterPresentationMode() {
  presentationMode.value = true
  setControlsVisible(false)
  if (hasSlides.value && !isPlaying.value) {
    startSlideshow()
  }
  if (!document.fullscreenElement) {
    try {
      await document.documentElement.requestFullscreen()
    } catch {
      // Some browser builds block fullscreen without direct user gesture chaining.
    }
  }
  statusMessage.value = 'Presentation mode enabled. Tap screen to show controls.'
}

function exitPresentationMode() {
  presentationMode.value = false
  setControlsVisible(true)
  if (document.fullscreenElement) {
    document.exitFullscreen().catch(() => {})
  }
}

function handleViewerTap() {
  if (swipeConsumedTap) {
    swipeConsumedTap = false
    return
  }
  if (touchMoved) return
  if (!presentationMode.value) return
  exitPresentationMode()
}

function normalizeFeedImage(entry, index) {
  if (typeof entry === 'string') {
    return { name: `public-${index + 1}`, url: entry, revocable: false }
  }
  if (entry && typeof entry.url === 'string') {
    return {
      name:
        typeof entry.name === 'string' && entry.name
          ? entry.name
          : `public-${index + 1}`,
      url: entry.url,
      revocable: false,
    }
  }
  return null
}

async function importPublicFeed() {
  publicFeedClicks.value += 1
  publicFeedStatus.value = `Import requested (#${publicFeedClicks.value})...`

  const trimmedUrl = normalizeHttpUrl(publicFeedUrl.value)
  if (!trimmedUrl) {
    publicFeedStatus.value = 'Enter a public feed URL first.'
    return
  }

  publicFeedUrl.value = trimmedUrl
  savePublicFeedSettings()
  publicFeedStatus.value = 'Loading public image feed...'

  try {
    const response = await fetch(trimmedUrl, { cache: 'no-store' })
    if (!response.ok) {
      throw new Error(`Feed request failed (${response.status}).`)
    }

    const body = await response.json()
    const rawImages = Array.isArray(body)
      ? body
      : Array.isArray(body.images)
        ? body.images
        : null
    if (!rawImages) {
      throw new Error("Feed JSON must be an array or an object with an 'images' array.")
    }

    const parsedSlides = rawImages
      .map((entry, index) => normalizeFeedImage(entry, index))
      .filter((slide) => slide !== null)

    if (parsedSlides.length === 0) {
      throw new Error('No valid image URLs were found in the feed.')
    }

    clearSlides()
    appendSlides(parsedSlides)
    statusMessage.value = `Loaded ${parsedSlides.length} image${parsedSlides.length === 1 ? '' : 's'} from public feed.`
    publicFeedStatus.value = 'Public feed import completed.'
  } catch (error) {
    publicFeedStatus.value =
      error instanceof Error ? error.message : 'Failed to load public image feed.'
  }
}

function seedFeedEditorFromSlides() {
  const urls = slides.value.map((slide) => slide.url).filter(Boolean)
  feedEditorText.value = urls.join('\n')
}

function parseEditorUrls() {
  return feedEditorText.value
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
}

function importFromEditor() {
  const urls = parseEditorUrls()
  if (urls.length === 0) {
    statusMessage.value = 'Feed editor is empty.'
    return
  }
  const editorSlides = urls.map((url, index) => ({
    name: `editor-${index + 1}`,
    url,
    revocable: false,
  }))
  clearSlides()
  appendSlides(editorSlides)
  statusMessage.value = `Loaded ${editorSlides.length} image${editorSlides.length === 1 ? '' : 's'} from feed editor.`
}

function downloadEditorJson() {
  const urls = parseEditorUrls()
  if (urls.length === 0) {
    statusMessage.value = 'Feed editor is empty.'
    return
  }
  const payload = {
    images: urls.map((url, index) => ({
      name: `photo-${index + 1}`,
      url,
    })),
  }
  const blob = new Blob([JSON.stringify(payload, null, 2)], {
    type: 'application/json',
  })
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = 'photos.json'
  link.click()
  URL.revokeObjectURL(link.href)
  statusMessage.value = 'Downloaded photos.json from feed editor.'
}

async function loadGoogleIdentityScript() {
  if (window.google?.accounts?.oauth2) {
    isGisReady.value = true
    return
  }

  const existingScript = document.querySelector(
    'script[data-google-gis="true"]',
  )
  if (existingScript) {
    existingScript.remove()
  }

  await new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = 'https://accounts.google.com/gsi/client'
    script.async = true
    script.defer = true
    script.dataset.googleGis = 'true'

    const timeout = window.setTimeout(() => {
      script.remove()
      reject(new Error('Timed out loading Google Identity Services script.'))
    }, 15000)

    script.onload = () => {
      window.clearTimeout(timeout)
      if (!window.google?.accounts?.oauth2) {
        reject(new Error('Google script loaded but OAuth API was unavailable.'))
        return
      }
      resolve()
    }

    script.onerror = () => {
      window.clearTimeout(timeout)
      reject(new Error('Failed to load Google Identity Services script.'))
    }

    document.head.appendChild(script)
  })

  isGisReady.value = true
}

async function retryGoogleIdentityScriptLoad() {
  isGisReady.value = false
  gisAttempts.value += 1
  driveStatus.value = `Retrying Google auth loader (attempt ${gisAttempts.value})...`
  try {
    await loadGoogleIdentityScript()
    driveStatus.value = 'Google auth ready. Enter your OAuth client ID.'
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'Unknown error.'
    const online = navigator.onLine ? 'online' : 'offline'
    driveStatus.value = `${reason} Browser network state: ${online}.`
  }
}

function ensureTokenClient() {
  const trimmedClientId = clientId.value.trim()
  if (!trimmedClientId) {
    throw new Error('Enter your Google OAuth client ID first.')
  }

  saveDriveSettings()

  tokenClient = window.google.accounts.oauth2.initTokenClient({
    client_id: trimmedClientId,
    scope: 'https://www.googleapis.com/auth/drive.readonly',
    callback: (response) => {
      if (response.error) {
        driveStatus.value = `Google auth failed: ${response.error}`
        return
      }
      accessToken.value = response.access_token
      isAuthorized.value = true
      driveStatus.value = 'Google Drive connected.'
    },
  })
}

function connectGoogleDrive() {
  try {
    if (!isGisReady.value) {
      throw new Error('Google auth library is not ready yet.')
    }
    ensureTokenClient()
    tokenClient.requestAccessToken({
      prompt: isAuthorized.value ? '' : 'consent',
    })
  } catch (error) {
    driveStatus.value =
      error instanceof Error ? error.message : 'Unable to connect to Google Drive.'
  }
}

function disconnectGoogleDrive() {
  accessToken.value = ''
  isAuthorized.value = false
  driveStatus.value = 'Google Drive disconnected.'
}

async function importGoogleDrivePhotos() {
  if (!accessToken.value) {
    driveStatus.value = 'Connect Google Drive before importing photos.'
    return
  }

  const limit = Math.max(1, importLimit.value)
  importLimit.value = limit
  saveDriveSettings()
  isDriveBusy.value = true
  driveStatus.value = 'Loading image list from Google Drive...'

  try {
    const nameContains = "mimeType contains 'image/' and trashed = false"
    const parsedFolderId = extractDriveFolderId(folderId.value)
    if (folderId.value.trim() && !parsedFolderId) {
      throw new Error('Folder value is not a valid Drive folder ID or URL.')
    }
    const inFolder = parsedFolderId ? ` and '${parsedFolderId}' in parents` : ''
    const q = `${nameContains}${inFolder}`
    const params = new URLSearchParams({
      q,
      pageSize: String(limit),
      fields: 'files(id,name,mimeType)',
      orderBy: 'modifiedTime desc',
      supportsAllDrives: 'true',
      includeItemsFromAllDrives: 'true',
    })

    const filesResponse = await fetch(
      `https://www.googleapis.com/drive/v3/files?${params.toString()}`,
      {
        headers: {
          Authorization: `Bearer ${accessToken.value}`,
        },
      },
    )

    if (!filesResponse.ok) {
      throw new Error(`Drive list failed (${filesResponse.status}).`)
    }

    const filesBody = await filesResponse.json()
    const files = Array.isArray(filesBody.files) ? filesBody.files : []

    if (files.length === 0) {
      driveStatus.value = 'No images found in Google Drive for the selected scope.'
      return
    }

    driveStatus.value = `Downloading ${files.length} image${files.length === 1 ? '' : 's'}...`

    const downloadedSlides = []
    for (const file of files) {
      const mediaResponse = await fetch(
        `https://www.googleapis.com/drive/v3/files/${file.id}?alt=media`,
        {
          headers: {
            Authorization: `Bearer ${accessToken.value}`,
          },
        },
      )

      if (!mediaResponse.ok) continue
      const blob = await mediaResponse.blob()
      downloadedSlides.push({
        name: file.name ?? `drive-${file.id}`,
        url: URL.createObjectURL(blob),
        revocable: true,
      })
    }

    if (downloadedSlides.length === 0) {
      driveStatus.value =
        'Found image entries, but none could be downloaded. Check Drive permissions.'
      return
    }

    clearSlides()
    appendSlides(downloadedSlides)
    statusMessage.value = `Loaded ${downloadedSlides.length} image${downloadedSlides.length === 1 ? '' : 's'} from Google Drive.`
    driveStatus.value = 'Google Drive import completed.'
  } catch (error) {
    driveStatus.value =
      error instanceof Error ? error.message : 'Failed to import Google Drive photos.'
  } finally {
    isDriveBusy.value = false
  }
}

watch(intervalSeconds, (value) => {
  if (value < 1) {
    intervalSeconds.value = 1
    return
  }
  if (isPlaying.value) startSlideshow()
  localStorage.setItem('slideshowIntervalSeconds', String(intervalSeconds.value))
})

watch(transitionMs, (value) => {
  if (value < 100) {
    transitionMs.value = 100
    return
  }
  localStorage.setItem('slideshowTransitionMs', String(transitionMs.value))
})

watch(shuffleEnabled, (value) => {
  localStorage.setItem('slideshowShuffleEnabled', String(value))
})

onMounted(async () => {
  updateOrientationLabel()
  window.addEventListener('resize', updateOrientationLabel)
  window.screen?.orientation?.addEventListener?.('change', updateOrientationLabel)
  window.addEventListener('orientationchange', updateOrientationLabel)
  orientationTimer = window.setInterval(updateOrientationLabel, 1000)

  try {
    await loadGoogleIdentityScript()
    driveStatus.value = 'Google auth ready. Enter your OAuth client ID.'
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'Unknown error.'
    const online = navigator.onLine ? 'online' : 'offline'
    driveStatus.value = `${reason} Browser network state: ${online}.`
  }
})

onBeforeUnmount(() => {
  stopSlideshow()
  revokeSlideUrls(slides.value)
  if (controlHideTimer !== null) clearTimeout(controlHideTimer)

  window.removeEventListener('resize', updateOrientationLabel)
  window.removeEventListener('orientationchange', updateOrientationLabel)
  window.screen?.orientation?.removeEventListener?.(
    'change',
    updateOrientationLabel,
  )

  if (orientationTimer !== null) {
    clearInterval(orientationTimer)
    orientationTimer = null
  }
})
</script>

<template>
  <main class="app" :class="{ presentation: presentationMode }">
    <div v-if="!presentationMode || controlsVisible" class="utility-bar">
      <span class="orientation-pill">Orientation: {{ orientationLabel }}</span>
      <button type="button" @click="showHomeHelp">Android Home</button>
      <button type="button" @click="reloadPage">Reload</button>
      <button type="button" @click="toggleFullscreen">Fullscreen</button>
      <button v-if="!presentationMode" type="button" :disabled="!hasSlides" @click="enterPresentationMode">
        Enter Presentation
      </button>
      <button v-else type="button" @click="exitPresentationMode">Exit Presentation</button>
    </div>

    <header v-if="!presentationMode || controlsVisible" class="controls">
      <h1>SkyLite Photo Frame</h1>
      <div class="control-row">
        <label class="file-input">
          <span>Upload photos</span>
          <input type="file" accept="image/*" multiple @change="loadFiles" />
        </label>
        <label class="interval">
          Delay (seconds)
          <input v-model.number="intervalSeconds" type="number" min="1" />
        </label>
        <label class="interval">
          Fade (ms)
          <input v-model.number="transitionMs" type="number" min="100" />
        </label>
        <label class="interval checkbox">
          <input v-model="shuffleEnabled" type="checkbox" />
          Shuffle
        </label>
      </div>

      <div class="drive-box">
        <h2>Public image feed (no OAuth)</h2>
        <div class="control-row">
          <label class="input-control">
            Feed URL
            <input
              v-model.trim="publicFeedUrl"
              type="text"
              placeholder="/photos.json or https://example.com/photos.json"
              @change="savePublicFeedSettings"
            />
          </label>
        </div>
        <div class="control-row buttons">
          <button type="button" @click="importPublicFeed">Import Public Feed</button>
        </div>
        <p class="status">{{ publicFeedStatus }}</p>
      </div>

      <div class="drive-box">
        <h2>Feed editor</h2>
        <p class="status">Paste one image URL per line, then import or download JSON.</p>
        <textarea
          v-model="feedEditorText"
          class="feed-editor"
          placeholder="https://example.com/photo-1.jpg&#10;https://example.com/photo-2.jpg"
        ></textarea>
        <div class="control-row buttons">
          <button type="button" @click="seedFeedEditorFromSlides">Use Current Slides</button>
          <button type="button" @click="importFromEditor">Import Editor URLs</button>
          <button type="button" @click="downloadEditorJson">Download photos.json</button>
        </div>
      </div>

      <div class="drive-box">
        <h2>Google Drive import</h2>
        <div class="control-row">
          <label class="input-control">
            OAuth Client ID
            <input
              v-model.trim="clientId"
              type="text"
              placeholder="Paste your Google OAuth client ID"
              @change="saveDriveSettings"
            />
          </label>
          <label class="input-control">
            Folder ID (optional)
            <input
              v-model.trim="folderId"
              type="text"
              placeholder="Drive folder ID or full folder URL"
              @change="saveDriveSettings"
            />
          </label>
          <label class="interval">
            Max images
            <input
              v-model.number="importLimit"
              type="number"
              min="1"
              max="100"
              @change="saveDriveSettings"
            />
          </label>
        </div>
        <div class="control-row buttons">
          <button type="button" :disabled="isDriveBusy" @click="retryGoogleIdentityScriptLoad">
            Retry Google Loader
          </button>
          <button
            type="button"
            :disabled="!canAuthorizeDrive || isDriveBusy"
            @click="connectGoogleDrive"
          >
            Connect Drive
          </button>
          <button type="button" :disabled="!isAuthorized" @click="disconnectGoogleDrive">
            Disconnect
          </button>
          <button
            type="button"
            :disabled="!isAuthorized || isDriveBusy"
            @click="importGoogleDrivePhotos"
          >
            {{ isDriveBusy ? 'Importing...' : 'Import Drive Photos' }}
          </button>
        </div>
        <p class="status">{{ driveStatus }}</p>
      </div>

      <div class="control-row buttons">
        <button type="button" :disabled="!hasSlides" @click="previousSlide">
          Previous
        </button>
        <button type="button" :disabled="!hasSlides" @click="toggleSlideshow">
          {{ isPlaying ? 'Pause' : 'Play' }}
        </button>
        <button type="button" :disabled="!hasSlides" @click="nextSlide">
          Next
        </button>
        <button type="button" @click="toggleFullscreen">Fullscreen</button>
        <button type="button" :disabled="!hasSlides" @click="clearSlides">
          Clear
        </button>
        <button type="button" @click="tryExitApp">Exit to Home</button>
      </div>
      <div class="progress-wrap" v-if="hasSlides">
        <div class="progress-bar" :style="{ width: `${progressPercent}%` }"></div>
      </div>
      <p class="status">{{ statusMessage }}</p>
      <p v-if="showExitHelp" class="exit-help">
        Browser apps cannot force Android navigation directly. Use host helper
        scripts: <code>./open-android-home.sh</code> for launcher/home and
        <code>./open-android-settings.sh</code> for Android settings.
      </p>
    </header>

    <section
      class="viewer"
      :style="{ '--slide-fade-ms': `${transitionMs}ms` }"
      @click="handleViewerTap"
      @touchstart.passive="onViewerTouchStart"
      @touchmove.passive="onViewerTouchMove"
      @touchend.passive="onViewerTouchEnd"
    >
      <transition name="fade-slide" mode="out-in">
        <img
          v-if="currentSlide"
          :key="currentSlide.url"
          :src="currentSlide.url"
          :alt="currentSlide.name"
          class="slide"
        />
        <div v-else class="placeholder">
          <p>No images loaded yet.</p>
        </div>
      </transition>

      <button
        v-if="presentationMode && controlsVisible"
        class="floating-exit"
        type="button"
        @click.stop="exitPresentationMode"
      >
        Exit
      </button>
      <div v-if="presentationMode && !controlsVisible" class="tap-hint">
        Tap anywhere to exit presentation
      </div>
      <div v-if="presentationMode && hasSlides" class="floating-hud">
        {{ slideCounterLabel }} · {{ isPlaying ? 'Playing' : 'Paused' }}
      </div>
    </section>
  </main>
</template>
