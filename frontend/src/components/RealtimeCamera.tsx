import { useState, useRef, useEffect, useCallback } from 'react'
import { Camera, Upload, Play, Square, RotateCcw, Wifi, WifiOff, Zap } from 'lucide-react'

interface RealtimeStats {
  fps: number; frame: number; shots: number; made: number; fg_pct: string; tracks: number;
  [key: string]: string | number
}
interface RealtimeResult {
  type: string; frame?: string; stats?: RealtimeStats; detections?: { balls: number; players: number }; message?: string
}

export default function RealtimeCamera() {
  const [isConnected, setIsConnected] = useState(false)
  const [isStreaming, setIsStreaming] = useState(false)
  const [stats, setStats] = useState<RealtimeStats | null>(null)
  const [detections, setDetections] = useState<{ balls: number; players: number } | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [mode, setMode] = useState<'upload' | 'camera'>('upload')

  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const wsRef = useRef<WebSocket | null>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const frameIntervalRef = useRef<number | null>(null)
  const annotatedImgRef = useRef<HTMLImageElement>(null)

  const connectWs = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const ws = new WebSocket(`${wsProtocol}//${window.location.host}/ws/realtime`)
    ws.onopen = () => { setIsConnected(true); setError(null) }
    ws.onmessage = (e) => {
      const d: RealtimeResult = JSON.parse(e.data)
      if (d.type === 'result' && d.frame && annotatedImgRef.current) {
        annotatedImgRef.current.src = `data:image/jpeg;base64,${d.frame}`
        if (d.stats) setStats(d.stats)
        if (d.detections) setDetections(d.detections)
      } else if (d.type === 'error') setError(d.message || 'Error')
    }
    ws.onclose = () => { setIsConnected(false); setIsStreaming(false) }
    ws.onerror = () => setError('WebSocket failed')
    wsRef.current = ws
  }, [])

  const disconnectWs = useCallback(() => {
    if (frameIntervalRef.current) { clearInterval(frameIntervalRef.current); frameIntervalRef.current = null }
    if (streamRef.current) { streamRef.current.getTracks().forEach(t => t.stop()); streamRef.current = null }
    wsRef.current?.close(); wsRef.current = null; setIsStreaming(false)
  }, [])

  const sendFrame = useCallback(() => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return
    const v = videoRef.current, c = canvasRef.current
    if (!v || !c) return
    const ctx = c.getContext('2d'); if (!ctx) return
    c.width = v.videoWidth || 640; c.height = v.videoHeight || 480
    ctx.drawImage(v, 0, 0)
    wsRef.current.send(JSON.stringify({ type: 'frame', data: c.toDataURL('image/jpeg', 0.7).split(',')[1] }))
  }, [])

  const startCamera = useCallback(async () => {
    try {
      const s = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment', width: 640, height: 480 } })
      streamRef.current = s
      if (videoRef.current) { videoRef.current.srcObject = s; await videoRef.current.play() }
      connectWs(); await new Promise(r => setTimeout(r, 500))
      setIsStreaming(true); frameIntervalRef.current = window.setInterval(sendFrame, 1000 / 15)
    } catch (e) { setError(`Camera denied: ${e}`) }
  }, [connectWs, sendFrame])

  const stopCamera = useCallback(() => { disconnectWs(); setIsStreaming(false) }, [disconnectWs])
  useEffect(() => () => disconnectWs(), [disconnectWs])

  return (
    <div className="card">
      {/* Header */}
      <div className="card-header">
        <div className="card-header-line" style={{ background: 'var(--orange-500)' }} />
        <h3 className="card-title" style={{ color: 'var(--orange-400)' }}>Real-Time</h3>
        {isStreaming && <Zap className="w-4 h-4 live-indicator" style={{ color: 'var(--orange-500)' }} />}
        <div className="ml-auto flex rounded-lg overflow-hidden" style={{ border: '1px solid rgba(249, 115, 22, 0.1)' }}>
          {(['upload', 'camera'] as const).map(m => (
            <button key={m} onClick={() => setMode(m)}
              className="flex items-center gap-1.5 px-3 py-1.5 text-[0.65rem] font-bold tracking-wider transition-all"
              style={{
                background: mode === m ? 'rgba(249, 115, 22, 0.08)' : 'transparent',
                color: mode === m ? 'var(--orange-400)' : 'var(--text-muted)',
                borderLeft: m === 'camera' ? '1px solid rgba(249, 115, 22, 0.08)' : 'none',
              }}>
              {m === 'upload' ? <Upload className="w-3 h-3" /> : <Camera className="w-3 h-3" />}
              {m === 'upload' ? 'FILE' : 'CAMERA'}
            </button>
          ))}
        </div>
      </div>

      {mode === 'camera' ? (
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <VideoPanel label="INPUT"><video ref={videoRef} className="w-full h-full object-cover" playsInline muted />
              {!isStreaming && <Overlay text={isConnected ? 'Ready' : 'Connecting...'} />}
            </VideoPanel>
            <VideoPanel label="AI OUTPUT"><img ref={annotatedImgRef} className="w-full h-full object-contain" alt="" />
              {!isStreaming && <Overlay text="Waiting" />}
            </VideoPanel>
          </div>
          <canvas ref={canvasRef} className="hidden" />
          <div className="flex items-center gap-3">
            {!isStreaming
              ? <button onClick={startCamera} className="btn btn-primary"><Play className="w-4 h-4" />Start</button>
              : <button onClick={stopCamera} className="btn btn-secondary"><Square className="w-4 h-4" />Stop</button>}
            <div className="flex items-center gap-2 ml-auto">
              {isConnected ? <Wifi className="w-3.5 h-3.5" style={{ color: 'var(--neon-green)' }} /> : <WifiOff className="w-3.5 h-3.5" style={{ color: 'var(--text-muted)' }} />}
              <span className="text-mono text-[0.6rem] font-bold" style={{ color: isConnected ? 'var(--neon-green)' : 'var(--text-muted)' }}>
                {isConnected ? 'CONNECTED' : 'OFFLINE'}
              </span>
            </div>
          </div>
        </div>
      ) : <VideoFileMode />}

      {/* Stats */}
      {stats && isStreaming && (
        <div className="mt-5 pt-5 stagger-children" style={{ borderTop: '1px solid rgba(249, 115, 22, 0.06)' }}>
          <div className="grid grid-cols-5 gap-3">
            {[
              { l: 'FPS', v: stats.fps, c: 'var(--orange-500)' },
              { l: 'SHOTS', v: stats['投篮'] ?? 0, c: 'var(--neon-cyan)' },
              { l: 'MADE', v: stats['命中'] ?? 0, c: 'var(--neon-green)' },
              { l: 'FG%', v: stats['命中率'] ?? '0%', c: 'var(--neon-gold)' },
              { l: 'TRACKS', v: stats['轨迹'] ?? 0, c: 'var(--neon-pink)' },
            ].map(s => (
              <div key={s.l} className="text-center p-2 rounded-lg" style={{ background: 'var(--surface-raised)', border: '1px solid rgba(255,255,255,0.03)' }}>
                <p className="text-[0.5rem] font-bold tracking-[0.12em] mb-1 uppercase" style={{ color: 'var(--text-muted)' }}>{s.l}</p>
                <p className="text-display text-xl font-black" style={{ color: s.c }}>{s.v}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {detections && isStreaming && (
        <div className="mt-3 flex items-center gap-4">
          <span className="text-mono text-[0.6rem] font-bold" style={{ color: 'var(--text-muted)' }}>
            BALLS: <span style={{ color: 'var(--orange-400)' }}>{detections.balls}</span>
          </span>
          <span className="text-mono text-[0.6rem] font-bold" style={{ color: 'var(--text-muted)' }}>
            PLAYERS: <span style={{ color: 'var(--neon-cyan)' }}>{detections.players}</span>
          </span>
        </div>
      )}

      {error && (
        <div className="mt-4 p-3 rounded-lg" style={{ background: 'rgba(244, 63, 94, 0.06)', border: '1px solid rgba(244, 63, 94, 0.15)' }}>
          <p className="text-sm" style={{ color: 'var(--neon-pink)' }}>{error}</p>
        </div>
      )}
    </div>
  )
}

function VideoPanel({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="relative">
      <span className="absolute top-3 left-3 z-10 text-mono text-[0.55rem] font-bold tracking-wider px-2 py-0.5 rounded"
        style={{ background: 'rgba(0, 0, 0, 0.7)', color: 'var(--orange-400)', border: '1px solid rgba(249, 115, 22, 0.15)' }}>
        {label}
      </span>
      <div className="relative aspect-video rounded-xl overflow-hidden"
        style={{ background: 'var(--surface-base)', border: 'var(--border-card)' }}>
        {children}
      </div>
    </div>
  )
}

function Overlay({ text }: { text: string }) {
  return (
    <div className="absolute inset-0 flex flex-col items-center justify-center gap-2"
      style={{ background: 'rgba(7, 8, 13, 0.85)' }}>
      <Play className="w-8 h-8" style={{ color: 'var(--text-muted)' }} />
      <p className="text-sm font-semibold" style={{ color: 'var(--text-secondary)' }}>{text}</p>
    </div>
  )
}

function VideoFileMode() {
  const [file, setFile] = useState<File | null>(null)
  const [analyzing, setAnalyzing] = useState(false)
  const [stats, setStats] = useState<RealtimeStats | null>(null)
  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const wsRef = useRef<WebSocket | null>(null)
  const annotatedImgRef = useRef<HTMLImageElement>(null)
  const intervalRef = useRef<number | null>(null)

  const start = useCallback(async () => {
    if (!file) return
    const v = videoRef.current; if (!v) return
    v.src = URL.createObjectURL(file); await v.play()
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const ws = new WebSocket(`${wsProtocol}//${window.location.host}/ws/realtime`)
    ws.onopen = () => {
      setAnalyzing(true)
      intervalRef.current = window.setInterval(() => {
        if (!v || !canvasRef.current || ws.readyState !== WebSocket.OPEN) return
        const ctx = canvasRef.current.getContext('2d'); if (!ctx) return
        canvasRef.current.width = v.videoWidth || 640; canvasRef.current.height = v.videoHeight || 480
        ctx.drawImage(v, 0, 0)
        ws.send(JSON.stringify({ type: 'frame', data: canvasRef.current.toDataURL('image/jpeg', 0.7).split(',')[1] }))
      }, 1000 / 10)
    }
    ws.onmessage = (e) => {
      const d = JSON.parse(e.data)
      if (d.type === 'result' && d.frame && annotatedImgRef.current) {
        annotatedImgRef.current.src = `data:image/jpeg;base64,${d.frame}`
        if (d.stats) setStats(d.stats)
      }
    }
    ws.onclose = () => setAnalyzing(false)
    ws.onerror = () => setAnalyzing(false)
    wsRef.current = ws
    v.onended = () => { if (intervalRef.current) clearInterval(intervalRef.current); ws.close(); setAnalyzing(false) }
  }, [file])

  useEffect(() => () => { if (intervalRef.current) clearInterval(intervalRef.current); wsRef.current?.close() }, [])

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <VideoPanel label="SOURCE">
          <video ref={videoRef} className="w-full h-full object-contain" playsInline muted />
          {!file && (
            <div className="absolute inset-0 flex items-center justify-center">
              <label className="cursor-pointer btn btn-primary">
                <Upload className="w-4 h-4" />Select Video
                <input type="file" accept="video/*" className="hidden" onChange={e => setFile(e.target.files?.[0] || null)} />
              </label>
            </div>
          )}
        </VideoPanel>
        <VideoPanel label="AI OUTPUT">
          <img ref={annotatedImgRef} className="w-full h-full object-contain" alt="" />
          {!analyzing && <Overlay text="Select a video" />}
        </VideoPanel>
      </div>
      <canvas ref={canvasRef} className="hidden" />
      <div className="flex items-center gap-3">
        {file && !analyzing && <button onClick={start} className="btn btn-primary"><Play className="w-4 h-4" />Analyze</button>}
        {file && <button onClick={() => { setFile(null); setStats(null) }} className="btn btn-ghost"><RotateCcw className="w-3.5 h-3.5" />Clear</button>}
      </div>
      {stats && analyzing && (
        <div className="grid grid-cols-5 gap-3 stagger-children">
          {[
            { l: 'FPS', v: stats.fps, c: 'var(--orange-500)' },
            { l: 'SHOTS', v: stats['投篮'] ?? 0, c: 'var(--neon-cyan)' },
            { l: 'MADE', v: stats['命中'] ?? 0, c: 'var(--neon-green)' },
            { l: 'FG%', v: stats['命中率'] ?? '0%', c: 'var(--neon-gold)' },
            { l: 'TRACKS', v: stats['轨迹'] ?? 0, c: 'var(--neon-pink)' },
          ].map(s => (
            <div key={s.l} className="text-center p-2 rounded-lg" style={{ background: 'var(--surface-raised)' }}>
              <p className="text-[0.5rem] font-bold tracking-[0.12em] mb-1 uppercase" style={{ color: 'var(--text-muted)' }}>{s.l}</p>
              <p className="text-display text-xl font-black" style={{ color: s.c }}>{s.v}</p>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
