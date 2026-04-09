const delayMs = Number(SLOW_MOTION_MS || 0)

if (delayMs > 0) {
  const end = Date.now() + delayMs
  while (Date.now() < end) {
  }
}
