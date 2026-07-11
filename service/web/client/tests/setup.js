import { vi } from 'vitest'

// jsdom 没有 EventSource，mock 它
global.EventSource = class MockEventSource {
  constructor(url) {
    this.url = url
    this.onmessage = null
    this.onerror = null
    this.CONNECTING = 0
    this.OPEN = 1
    this.CLOSED = 2
    this.readyState = 1
    // 不自动触发事件，让 test 控制
  }
  addEventListener(event, fn) {
    this[`on${event}`] = fn
  }
  close() {
    this.readyState = 2
  }
}
