import { useState, useRef, useCallback } from 'react'
import { Upload, Film, Loader2, Zap, CheckCircle2 } from 'lucide-react'

interface VideoUploaderProps {
  onUploadComplete: (taskId: string) => void
  isAnalyzing: boolean
  progress: number
}

export default function VideoUploader({ onUploadComplete, isAnalyzing, progress }: VideoUploaderProps) {
  const [isDragging, setIsDragging] = useState(false)
  const [isUploading, setIsUploading] = useState(false)
  const [fileName, setFileName] = useState<string | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
    const file = e.dataTransfer.files[0]
    if (file && file.type.startsWith('video/')) {
      setFileName(file.name)
      uploadFile(file)
    }
  }, [])

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      setFileName(file.name)
      uploadFile(file)
    }
  }

  const uploadFile = async (file: File) => {
    setIsUploading(true)
    const formData = new FormData()
    formData.append('file', file)
    try {
      const res = await fetch('/api/v1/analyze', { method: 'POST', body: formData })
      if (!res.ok) throw new Error('Upload failed')
      const data = await res.json()
      onUploadComplete(data.task_id)
    } catch (err) {
      alert('Upload failed: ' + (err instanceof Error ? err.message : 'Unknown'))
    } finally {
      setIsUploading(false)
    }
  }

  return (
    <div
      className="relative cursor-pointer transition-all duration-300"
      style={{
        background: isDragging
          ? 'linear-gradient(135deg, rgba(249, 115, 22, 0.06), rgba(249, 115, 22, 0.02))'
          : 'var(--surface-card)',
        borderRadius: '16px',
        border: isDragging
          ? '2px dashed var(--orange-500)'
          : '2px dashed rgba(249, 115, 22, 0.12)',
        boxShadow: isDragging ? 'var(--glow-orange)' : 'var(--shadow-card)',
        pointerEvents: isAnalyzing ? 'none' : 'auto',
        opacity: isAnalyzing ? 0.85 : 1,
      }}
      onDragOver={(e) => { e.preventDefault(); setIsDragging(true) }}
      onDragLeave={() => setIsDragging(false)}
      onDrop={handleDrop}
      onClick={() => !isAnalyzing && fileInputRef.current?.click()}
    >
      <input ref={fileInputRef} type="file" accept="video/*" className="hidden" onChange={handleFileSelect} />

      <div className="flex flex-col items-center justify-center py-12 px-6">
        {isUploading ? (
          <>
            <div className="w-14 h-14 rounded-full flex items-center justify-center mb-4 animate-pulse-glow"
              style={{ background: 'rgba(249, 115, 22, 0.1)', border: '1px solid rgba(249, 115, 22, 0.2)' }}>
              <Loader2 className="w-7 h-7 animate-spin" style={{ color: 'var(--orange-500)' }} />
            </div>
            <p className="text-display text-lg font-bold tracking-wider mb-1" style={{ color: 'var(--orange-400)' }}>
              Uploading
            </p>
            <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>
              {fileName ? `Sending ${fileName}...` : 'Sending to analysis engine...'}
            </p>
          </>
        ) : isAnalyzing ? (
          <>
            <div className="w-14 h-14 rounded-full flex items-center justify-center mb-4 animate-pulse-glow"
              style={{ background: 'rgba(249, 115, 22, 0.1)', border: '1px solid rgba(249, 115, 22, 0.2)' }}>
              <Zap className="w-7 h-7" style={{ color: 'var(--orange-500)' }} />
            </div>
            <p className="text-display text-lg font-bold tracking-wider mb-3" style={{ color: 'var(--orange-400)' }}>
              Analyzing
            </p>
            <div className="w-64 mb-2">
              <div className="progress-track">
                <div className="progress-fill" style={{ width: `${progress * 100}%` }} />
              </div>
            </div>
            <p className="text-mono text-xs" style={{ color: 'var(--text-muted)' }}>
              {(progress * 100).toFixed(0)}% complete
            </p>
          </>
        ) : (
          <>
            <div className="w-16 h-16 rounded-full flex items-center justify-center mb-5 transition-all duration-300"
              style={{
                background: isDragging ? 'rgba(249, 115, 22, 0.1)' : 'var(--surface-raised)',
                border: `1px solid ${isDragging ? 'rgba(249, 115, 22, 0.25)' : 'rgba(255, 255, 255, 0.05)'}`,
                boxShadow: isDragging ? 'var(--glow-orange)' : 'none',
                transform: isDragging ? 'scale(1.08)' : 'scale(1)',
              }}>
              {isDragging
                ? <Film className="w-7 h-7" style={{ color: 'var(--orange-500)' }} />
                : <Upload className="w-7 h-7" style={{ color: 'var(--text-muted)' }} />
              }
            </div>
            <p className="text-display text-xl font-bold tracking-wider mb-1"
              style={{ color: isDragging ? 'var(--orange-400)' : 'var(--text-bright)' }}>
              {isDragging ? 'Drop it here' : 'Upload Video'}
            </p>
            <p className="text-sm mb-4" style={{ color: 'var(--text-secondary)' }}>
              Drag & drop or click to browse
            </p>
            <div className="flex items-center gap-2">
              {['MP4', 'MOV', 'AVI', 'WEBM'].map(f => (
                <span key={f} className="text-mono text-[0.55rem] font-medium px-2 py-0.5 rounded"
                  style={{ background: 'var(--surface-raised)', color: 'var(--text-muted)', border: '1px solid rgba(255,255,255,0.04)' }}>
                  {f}
                </span>
              ))}
            </div>
          </>
        )}
      </div>

      {/* Success checkmark overlay when complete */}
      {!isUploading && !isAnalyzing && progress >= 1 && (
        <div className="absolute top-3 right-3">
          <CheckCircle2 size={20} style={{ color: 'var(--neon-green)' }} />
        </div>
      )}
    </div>
  )
}
