const loadingTexts = [
    "Initializing core systems...",
    "Loading player data...",
    "Syncing with server...",
    "Preparing world...",
    "Loading assets...",
    "Almost there..."
]

const tips = [
    "Press F1 to open the help menu",
    "Use /report to contact staff",
    "Visit the job center to find work",
    "Check your inventory with TAB",
    "Use your phone to call other players",
    "Follow traffic laws to avoid tickets",
    "Visit the hospital when injured",
    "Bank your money to keep it safe"
]

const statuses = [
    "Connecting",
    "Handshaking",
    "Downloading resources",
    "Loading scripts",
    "Spawning player",
    "Finalizing"
]

let currentProgress = 0
let targetProgress = 0
let tipIndex = 0

function createParticles() {
    const container = document.getElementById('particles')
    const particleCount = 30

    for (let i = 0; i < particleCount; i++) {
        const particle = document.createElement('div')
        particle.className = 'particle'
        particle.style.left = Math.random() * 100 + '%'
        particle.style.animationDelay = Math.random() * 15 + 's'
        particle.style.animationDuration = (10 + Math.random() * 10) + 's'
        container.appendChild(particle)
    }
}

function updateProgress() {
    const bar = document.getElementById('progressBar')
    const percentage = document.getElementById('progressPercentage')
    const status = document.getElementById('progressStatus')
    const loadingText = document.getElementById('loadingText')

    if (currentProgress < targetProgress) {
        currentProgress += (targetProgress - currentProgress) * 0.05
    }

    if (currentProgress > targetProgress) {
        currentProgress = targetProgress
    }

    const displayProgress = Math.min(Math.floor(currentProgress), 100)

    bar.style.width = displayProgress + '%'
    percentage.textContent = displayProgress + '%'

    const statusIdx = Math.min(
        Math.floor((displayProgress / 100) * statuses.length),
        statuses.length - 1
    )
    status.textContent = statuses[statusIdx]

    const textIdx = Math.min(
        Math.floor((displayProgress / 100) * loadingTexts.length),
        loadingTexts.length - 1
    )
    loadingText.textContent = loadingTexts[textIdx]

    if (displayProgress >= 100) {
        setTimeout(() => {
            loadingText.textContent = "Welcome!"
        }, 500)
    }
}

function rotateTips() {
    const tipText = document.getElementById('tipText')

    tipText.style.opacity = '0'

    setTimeout(() => {
        tipIndex = (tipIndex + 1) % tips.length
        tipText.textContent = tips[tipIndex]
        tipText.style.opacity = '1'
    }, 500)
}

function simulateLoading() {
    let progress = 0

    const interval = setInterval(() => {
        progress += Math.random() * 3

        if (progress > 100) {
            progress = 100
            clearInterval(interval)
        }

        targetProgress = progress
    }, 200)
}

window.addEventListener('load', () => {
    createParticles()
    simulateLoading()

    setInterval(updateProgress, 50)
    setInterval(rotateTips, 6000)
})

window.addEventListener('message', (event) => {
    const data = event.data

    if (data.type === 'setProgress') {
        targetProgress = data.value
    }
})