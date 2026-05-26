import { useState, useRef, useCallback, useEffect } from 'react'

interface RealtimeStats {
  fps: number; frame: number; [key: string]: string | number
}

interface RealtimeResult {
  type: string
  frame?: string
  stats?: RealtimeStats
  detections?: { balls: number; players: number }
  message?: string
}

interface UseWebSocketOptions {
  /** 帧发送间隔（ms），默认 66（约 15fps） */
  frameInterval?: number
}

/** WebSocket 实时连接、帧收发、自动重连封装 */
export function useWebSocket(options: UseWebSocketOptions = {}) {
  const { frameInterval = 66 } = options

  const [isConnected, setIsConnected] = useState(false)
  const [isStreaming, setIsStreaming] = useState(false)
  const [stats, setStats] = useState<RealtimeStats | null>(null)
  const [detections, setDetections] = useState<{ balls: number; players: number } | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [annotatedSrc, setAnnotatedSrc] = useState<string>('')

  const wsRef = useRef<WebSocket | null>(null)
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return
    const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const ws = new WebSocket(`${proto}//${window.location.host}/ws/realtime`)

    ws.onopen = () => { setIsConnected(true); setError(null) }
    ws.onmessage = (e) => {
      const d: RealtimeResult = JSON.parse(e.data)
      if (d.type === 'result') {
        if (d.frame) setAnnotatedSrc(`data:image/jpeg;base64,${d.frame}`)
        if (d.stats) setStats(d.stats)
        if (d.detections) setDetections(d.detections)
      } else if (d.type === 'error') {
        setError(d.message || 'Error')
      }
    }
    ws.onclose = () => { setIsConnected(false); setIsStreaming(false) }
    ws.onerror = () => setError('WebSocket failed')

    wsRef.current = ws
  }, [])

  const disconnect = useCallback(() => {
    if (intervalRef.current) { clearInterval(intervalRef.current); intervalRef.current = null }
    wsRef.current?.close()
    wsRef.current = null
    setIsStreaming(false)
  }, [])

  const sendFrame = useCallback((videoEl: HTMLVideoElement, canvasEl: HTMLCanvasElement) => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return
    const ctx = canvasEl.getContext('2d')
    if (!ctx) return
    canvasEl.width = videoEl.videoWidth || 640
    canvasEl.height = videoEl.videoHeight || 480
    ctx.drawImage(videoEl, 0, 0)
    wsRef.current.send(JSON.stringify({
      type: 'frame',
      data: canvasEl.toDataURL('image/jpeg', 0.7).split(',')[1],
    }))
  }, [])

  const startStreaming = useCallback((videoEl: HTMLVideoElement, canvasEl: HTMLCanvasElement) => {
    connect()
    setTimeout(() => {
      setIsStreaming(true)
      intervalRef.current = setInterval(() => sendFrame(videoEl, canvasEl), frameInterval)
    }, 300)
  }, [connect, sendFrame, frameInterval])

  const stopStreaming = useCallback(() => {
    disconnect()
  }, [disconnect])

  useEffect(() => () => disconnect(), [disconnect])

  return {
    isConnected,
    isStreaming,
    stats,
    detections,
    error,
    annotatedSrc,
    connect,
    disconnect,
    startStreaming,
    stopStreaming,
    setError,
  }
}
