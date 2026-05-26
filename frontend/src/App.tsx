import { useState } from 'react'
import { Upload, BarChart3, Video, Activity, Crosshair, Zap } from 'lucide-react'
import VideoUploader from './components/VideoUploader'
import StatsPanel from './components/StatsPanel'
import RealtimeCamera from './components/RealtimeCamera'
import ParticleBackground from './components/ParticleBackground'
import type { AnalysisResult } from './types'

type View = 'upload' | 'dashboard' | 'live'

export default function App() {
  const [result, setResult] = useState<AnalysisResult | null>(null)
  const [isAnalyzing, setIsAnalyzing] = useState(false)
  const [progress, setProgress] = useState(0)
  const [view, setView] = useState<View>('upload')

  const handleUploadComplete = (id: string) => {
    setIsAnalyzing(true)
    setProgress(0)
    pollStatus(id)
  }

  const pollStatus = async (id: string) => {
    let retries = 0
    const maxRetries = 150  // 最多轮询 150 次（约 2 分钟）
    const poll = setInterval(async () => {
      try {
        const res = await fetch(`/api/v1/status/${id}`)
        if (!res.ok) {
          retries++
          if (retries >= maxRetries) {
            clearInterval(poll)
            setIsAnalyzing(false)
            alert('Analysis timed out. Please try again.')
          }
          return
        }
        const data = await res.json()
        retries = 0  // 重置重试计数

        if (data.status === 'processing') {
          setProgress(data.progress)
        } else if (data.status === 'completed') {
          clearInterval(poll)
          const resultRes = await fetch(`/api/v1/results/${id}`)
          const resultData = await resultRes.json()
          setResult(resultData)
          setIsAnalyzing(false)
          setProgress(1)
          setView('dashboard')
        } else if (data.status === 'failed') {
          clearInterval(poll)
          setIsAnalyzing(false)
          alert('Analysis failed: ' + (data.error || 'Unknown error'))
        }
      } catch {
        retries++
        if (retries >= maxRetries) {
          clearInterval(poll)
          setIsAnalyzing(false)
          alert('Lost connection to server.')
        }
      }
    }, 800)

    // 页面卸载时清除轮询
    const cleanup = () => clearInterval(poll)
    window.addEventListener('beforeunload', cleanup)
    return () => {
      clearInterval(poll)
      window.removeEventListener('beforeunload', cleanup)
    }
  }

  const handleReset = () => {
    setResult(null)
    setIsAnalyzing(false)
    setProgress(0)
    setView('upload')
  }

  const handleViewChange = (v: View) => {
    if (v === 'dashboard' && !result) return
    setView(v)
  }

  const viewTitles: Record<View, string> = {
    upload: 'Upload & Analyze',
    dashboard: 'Shot Analytics',
    live: 'Real-Time Detection',
  }

  return (
    <div className="app-layout">
      <ParticleBackground />

      {/* Sidebar */}
      <aside className="sidebar">
        <div className="sidebar-logo">
          <div className="sidebar-logo-icon">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
              <circle cx="12" cy="12" r="10" stroke="white" strokeWidth="1.5" />
              <path d="M12 2C12 2 8 8 8 12C8 16 12 22 12 22" stroke="white" strokeWidth="1.2" />
              <path d="M12 2C12 2 16 8 16 12C16 16 12 22 12 22" stroke="white" strokeWidth="1.2" />
              <line x1="2" y1="12" x2="22" y2="12" stroke="white" strokeWidth="1.2" />
            </svg>
          </div>
          <div className="sidebar-brand">
            <h1>COURTSIDE</h1>
            <p>Analytics</p>
          </div>
        </div>

        <nav className="sidebar-nav">
          <div className="nav-section-label">Analysis</div>

          <button
            className={`nav-item ${view === 'upload' ? 'active' : ''}`}
            onClick={() => handleViewChange('upload')}
          >
            <span className="nav-item-icon"><Upload size={18} /></span>
            <span>Upload Video</span>
          </button>

          <button
            className={`nav-item ${view === 'dashboard' ? 'active' : ''} ${!result ? 'disabled' : ''}`}
            onClick={() => handleViewChange('dashboard')}
          >
            <span className="nav-item-icon"><BarChart3 size={18} /></span>
            <span>Shot Analytics</span>
            {result && <span className="nav-item-badge">Ready</span>}
          </button>

          <button
            className={`nav-item ${view === 'live' ? 'active' : ''}`}
            onClick={() => handleViewChange('live')}
          >
            <span className="nav-item-icon"><Video size={18} /></span>
            <span>Live Detection</span>
          </button>

          <div className="nav-section-label" style={{ marginTop: '1rem' }}>Insights</div>

          <div className="nav-item disabled">
            <span className="nav-item-icon"><Activity size={18} /></span>
            <span>Shot History</span>
          </div>

          <div className="nav-item disabled">
            <span className="nav-item-icon"><Crosshair size={18} /></span>
            <span>Player Stats</span>
          </div>
        </nav>

        <div className="sidebar-footer">
          <div className="sidebar-status">
            <div className="status-dot" />
            <span className="status-text">SYSTEM ONLINE</span>
          </div>
        </div>
      </aside>

      {/* Main Area */}
      <div className="main-area">
        {/* Top Bar */}
        <div className="top-bar">
          <span className="top-bar-title">{viewTitles[view]}</span>
          <div className="top-bar-actions">
            {isAnalyzing && (
              <div className="flex items-center gap-2">
                <Zap size={14} style={{ color: 'var(--orange-500)' }} className="live-indicator" />
                <span className="text-mono text-xs" style={{ color: 'var(--orange-400)' }}>
                  {(progress * 100).toFixed(0)}%
                </span>
              </div>
            )}
            {result && view !== 'dashboard' && (
              <button onClick={() => setView('dashboard')} className="btn btn-ghost" style={{ fontSize: '0.65rem' }}>
                <BarChart3 size={14} /> View Results
              </button>
            )}
          </div>
        </div>

        {/* Content */}
        <main className="main-content">
          {view === 'upload' && (
            <section className="animate-fade-in">
              {/* Hero */}
              <div className="text-center mb-10">
                <div className="flex items-center justify-center gap-3 mb-3">
                  <div className="animate-basketball">
                    <svg width="36" height="36" viewBox="0 0 24 24" fill="none">
                      <circle cx="12" cy="12" r="10" stroke="var(--orange-500)" strokeWidth="1.5" />
                      <path d="M12 2C12 2 8 8 8 12C8 16 12 22 12 22" stroke="var(--orange-500)" strokeWidth="1.2" />
                      <path d="M12 2C12 2 16 8 16 12C16 16 12 22 12 22" stroke="var(--orange-500)" strokeWidth="1.2" />
                      <line x1="2" y1="12" x2="22" y2="12" stroke="var(--orange-500)" strokeWidth="1.2" />
                    </svg>
                  </div>
                </div>
                <h1 className="text-display text-3xl md:text-4xl font-black mb-2"
                  style={{
                    background: 'linear-gradient(135deg, var(--orange-400), var(--orange-600))',
                    WebkitBackgroundClip: 'text',
                    WebkitTextFillColor: 'transparent',
                  }}>
                  SHOT ANALYZER
                </h1>
                <p className="text-sm" style={{ color: 'var(--text-secondary)', maxWidth: '400px', margin: '0 auto' }}>
                  AI-powered basketball shot tracking and analytics platform
                </p>
              </div>

              <div style={{ maxWidth: '560px', margin: '0 auto' }}>
                <VideoUploader
                  onUploadComplete={handleUploadComplete}
                  isAnalyzing={isAnalyzing}
                  progress={progress}
                />
              </div>

              {/* Feature Cards */}
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mt-10 stagger-children" style={{ maxWidth: '720px', margin: '2.5rem auto 0' }}>
                <FeatureCard
                  icon={<Crosshair size={18} />}
                  title="Shot Detection"
                  description="AI-powered detection of every shot attempt with make/miss classification"
                  color="var(--orange-500)"
                />
                <FeatureCard
                  icon={<BarChart3 size={18} />}
                  title="Zone Analytics"
                  description="Court zone breakdowns, heatmaps, and shot distribution analysis"
                  color="var(--neon-cyan)"
                />
                <FeatureCard
                  icon={<Activity size={18} />}
                  title="Trajectory Tracking"
                  description="Release angle, entry angle, and shot arc measurement"
                  color="var(--neon-green)"
                />
              </div>
            </section>
          )}

          {view === 'dashboard' && result && (
            <StatsPanel result={result} onReset={handleReset} />
          )}

          {view === 'live' && (
            <section className="animate-fade-in">
              <div className="mb-6">
                <h2 className="text-display text-lg font-bold tracking-wider mb-1" style={{ color: 'var(--text-bright)' }}>
                  Real-Time Detection
                </h2>
                <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                  Live camera feed or video file analysis with instant AI detection
                </p>
              </div>
              <RealtimeCamera />
            </section>
          )}
        </main>

        {/* Footer */}
        <footer className="app-footer">
          <p>COURTSIDE ANALYTICS v1.0.0 &mdash; AI-POWERED BASKETBALL SHOT TRACKING</p>
        </footer>
      </div>

      {/* Mobile Navigation */}
      <nav className="mobile-nav">
        <button
          className={`mobile-nav-item ${view === 'upload' ? 'active' : ''}`}
          onClick={() => handleViewChange('upload')}
        >
          <Upload size={18} />
          <span>Upload</span>
        </button>
        <button
          className={`mobile-nav-item ${view === 'dashboard' ? 'active' : ''}`}
          onClick={() => handleViewChange('dashboard')}
          style={{ opacity: result ? 1 : 0.4 }}
        >
          <BarChart3 size={18} />
          <span>Stats</span>
        </button>
        <button
          className={`mobile-nav-item ${view === 'live' ? 'active' : ''}`}
          onClick={() => handleViewChange('live')}
        >
          <Video size={18} />
          <span>Live</span>
        </button>
      </nav>
    </div>
  )
}

function FeatureCard({ icon, title, description, color }: {
  icon: React.ReactNode; title: string; description: string; color: string
}) {
  return (
    <div className="card text-center" style={{ padding: '1.25rem' }}>
      <div className="flex items-center justify-center mb-3">
        <div className="w-10 h-10 rounded-lg flex items-center justify-center"
          style={{ background: `${color}12`, color }}>
          {icon}
        </div>
      </div>
      <h3 className="text-display text-xs font-bold tracking-wider mb-1.5" style={{ color: 'var(--text-bright)' }}>
        {title}
      </h3>
      <p className="text-xs" style={{ color: 'var(--text-secondary)', lineHeight: '1.5' }}>
        {description}
      </p>
    </div>
  )
}
