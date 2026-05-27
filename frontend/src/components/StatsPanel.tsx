import { RotateCcw, Download, TrendingUp, Target, Crosshair, Ruler, Flame, Trophy, Zap, Gauge, Timer, ArrowUpRight, FileSpreadsheet, FileText } from 'lucide-react'
import ShotChart from './ShotChart'
import ZoneHeatmap from './ZoneHeatmap'
import DistanceChart from './DistanceChart'
import StreakDisplay from './StreakDisplay'
import type { AnalysisResult } from '../types'
import { TYPE_LABELS, TYPE_COLORS_VAR } from '../constants'

interface StatsPanelProps {
  result: AnalysisResult
  onReset: () => void
}

export default function StatsPanel({ result, onReset }: StatsPanelProps) {
  const { summary, by_type, by_zone, distance_distribution, streaks, angles, shots, annotated_video, kinematics } = result

  const threePtMade = by_type?.three_point?.made ?? 0
  const twoPtMade = (summary.made_shots - threePtMade)
  const effectiveFG = summary.total_shots > 0
    ? ((summary.made_shots + 0.5 * threePtMade) / summary.total_shots * 100)
    : 0
  const estPoints = threePtMade * 3 + twoPtMade * 2
  const ptsPerShot = summary.total_shots > 0 ? (estPoints / summary.total_shots) : 0

  return (
    <div className="animate-fade-in-up space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h2 className="text-display text-xl font-bold tracking-wider" style={{ color: 'var(--text-bright)' }}>
            Analysis Complete
          </h2>
          <p className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>
            {summary.total_shots} shots detected in {summary.video_duration?.toFixed(0) || '—'}s video
          </p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <button onClick={onReset} className="btn btn-ghost flex items-center gap-2 text-xs">
            <RotateCcw size={14} />
            New Video
          </button>
          {annotated_video && (
            <a href={annotated_video} download className="btn btn-secondary flex items-center gap-2 text-xs">
              <Download size={14} />
              Video
            </a>
          )}
          {result.task_id && (
            <>
              <a href={`/api/v1/export/excel/${result.task_id}`} className="btn btn-ghost flex items-center gap-2 text-xs"
                style={{ color: 'var(--neon-green)' }}>
                <FileSpreadsheet size={14} />
                Excel
              </a>
              <a href={`/api/v1/export/pdf/${result.task_id}`} className="btn btn-ghost flex items-center gap-2 text-xs"
                style={{ color: 'var(--neon-pink)' }}>
                <FileText size={14} />
                PDF
              </a>
            </>
          )}
        </div>
      </div>

      {/* Primary Stats */}
      <section className="grid grid-cols-2 sm:grid-cols-4 gap-3 stagger-children">
        <StatCard
          label="Total Shots"
          value={summary.total_shots}
          color="var(--orange-500)"
          icon={<Crosshair className="w-4 h-4" />}
        />
        <StatCard
          label="Shots Made"
          value={summary.made_shots}
          color="var(--neon-green)"
          icon={<Target className="w-4 h-4" />}
        />
        <StatCard
          label="Field Goal %"
          value={(summary.overall_percentage * 100).toFixed(1)}
          suffix="%"
          color="var(--neon-cyan)"
          icon={<TrendingUp className="w-4 h-4" />}
        />
        <StatCard
          label="Effective FG%"
          value={effectiveFG.toFixed(1)}
          suffix="%"
          color="var(--neon-gold)"
          icon={<Trophy className="w-4 h-4" />}
        />
      </section>

      {/* Secondary Stats */}
      <section className="grid grid-cols-2 sm:grid-cols-4 gap-3 stagger-children">
        <StatCard
          label="Est. Points"
          value={estPoints}
          color="var(--neon-pink)"
          icon={<Zap className="w-4 h-4" />}
        />
        <StatCard
          label="Points / Shot"
          value={ptsPerShot.toFixed(2)}
          color="var(--neon-purple)"
        />
        <StatCard
          label="Avg Distance"
          value={summary.average_distance.toFixed(1)}
          suffix="m"
          color="var(--orange-400)"
          icon={<Ruler className="w-4 h-4" />}
        />
        <StatCard
          label="Video Duration"
          value={summary.video_duration?.toFixed(0) || '—'}
          suffix="s"
          color="var(--text-secondary)"
        />
      </section>

      {/* Kinematics */}
      {kinematics && kinematics.avg_speed > 0 && (
        <section className="grid grid-cols-3 gap-3 stagger-children">
          <StatCard
            label="Avg Shot Speed"
            value={kinematics.avg_speed.toFixed(1)}
            suffix="m/s"
            color="var(--neon-cyan)"
            icon={<Gauge className="w-4 h-4" />}
          />
          <StatCard
            label="Avg Flight Time"
            value={kinematics.avg_flight_time.toFixed(2)}
            suffix="s"
            color="var(--neon-green)"
            icon={<Timer className="w-4 h-4" />}
          />
          <StatCard
            label="Avg Arc Height"
            value={kinematics.avg_arc_height.toFixed(2)}
            suffix="m"
            color="var(--neon-pink)"
            icon={<ArrowUpRight className="w-4 h-4" />}
          />
        </section>
      )}

      {/* Streaks */}
      {streaks && (
        <section>
          <StreakDisplay
            maxMadeStreak={streaks.max_made_streak}
            maxMissedStreak={streaks.max_missed_streak}
          />
        </section>
      )}

      {/* Charts Row 1 */}
      <section className="grid grid-cols-1 lg:grid-cols-2 gap-5">
        <Card title="Shot Breakdown" color="var(--orange-500)">
          <ShotChart data={by_type} />
        </Card>
        <Card title="Court Zones" color="var(--neon-green)">
          <ZoneHeatmap data={by_zone || {}} />
        </Card>
      </section>

      {/* Charts Row 2 */}
      <section className="grid grid-cols-1 lg:grid-cols-2 gap-5">
        <Card title="Distance Distribution" color="var(--neon-cyan)">
          <DistanceChart data={distance_distribution || {}} />
        </Card>
        {angles && Object.keys(angles).length > 0 && (
          <Card title="Release Angles" color="var(--neon-pink)">
            <div className="grid grid-cols-2 gap-3 mb-4">
              <AngleStat label="Average" value={angles.avg_release_angle} highlight />
              <AngleStat label="Std Dev" value={angles.std_release_angle} />
              <AngleStat label="Min" value={angles.min_release_angle} />
              <AngleStat label="Max" value={angles.max_release_angle} />
            </div>
            <AngleGauge value={angles.avg_release_angle} />
          </Card>
        )}
      </section>

      {/* Shot Log Table */}
      <Card title="Shot Log" color="var(--neon-gold)">
        <ShotDetailsTable shots={shots} />
      </Card>

      {/* Annotated Video */}
      {annotated_video && (
        <Card title="Annotated Replay" color="var(--orange-500)">
          <div className="video-container">
            <video
              src={annotated_video}
              controls
              className="w-full rounded-xl"
              style={{ maxHeight: '480px' }}
            />
          </div>
        </Card>
      )}
    </div>
  )
}

// ─── Shared Components ───

function Card({ title, color, children }: { title: string; color: string; children: React.ReactNode }) {
  return (
    <div className="card">
      <div className="card-header">
        <div className="card-header-line" style={{ background: color }} />
        <h3 className="card-title" style={{ color }}>{title}</h3>
      </div>
      {children}
    </div>
  )
}

function StatCard({ label, value, suffix, color, icon }: {
  label: string; value: string | number; suffix?: string; color: string; icon?: React.ReactNode
}) {
  return (
    <div className="stat-card group">
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: '2px', background: `linear-gradient(90deg, transparent, ${color}, transparent)` }} />
      <div className="stat-card-icon">
        {icon && <span style={{ color, opacity: 0.6 }}>{icon}</span>}
        <span className="stat-label">{label}</span>
      </div>
      <div>
        <span className="stat-value" style={{ color }}>{value}</span>
        {suffix && <span className="stat-unit">{suffix}</span>}
      </div>
    </div>
  )
}

function AngleStat({ label, value, highlight }: { label: string; value: number; highlight?: boolean }) {
  return (
    <div className="text-center p-3 rounded-lg" style={{
      background: highlight ? 'rgba(244, 63, 94, 0.06)' : 'var(--surface-raised)',
      border: highlight ? '1px solid rgba(244, 63, 94, 0.15)' : '1px solid rgba(255,255,255,0.03)',
    }}>
      <p className="stat-label mb-1">{label}</p>
      <p className="text-mono text-xl font-bold" style={{ color: highlight ? 'var(--neon-pink)' : 'var(--orange-400)' }}>
        {value.toFixed(1)}<span className="text-xs opacity-50">&deg;</span>
      </p>
    </div>
  )
}

function AngleGauge({ value }: { value: number }) {
  const optimalMin = 40
  const optimalMax = 55
  const gaugeMax = 80
  const pct = Math.min(value / gaugeMax, 1)

  return (
    <div className="relative h-8 rounded-lg overflow-hidden" style={{ background: 'var(--surface-raised)', border: '1px solid rgba(255,255,255,0.03)' }}>
      <div className="absolute inset-y-0" style={{
        left: `${(optimalMin / gaugeMax) * 100}%`,
        width: `${((optimalMax - optimalMin) / gaugeMax) * 100}%`,
        background: 'rgba(34, 197, 94, 0.08)',
        borderLeft: '1px solid rgba(34, 197, 94, 0.25)',
        borderRight: '1px solid rgba(34, 197, 94, 0.25)',
      }} />
      <div className="absolute inset-y-0 w-1 rounded-full transition-all duration-700"
        style={{
          left: `${pct * 100}%`,
          background: 'var(--neon-pink)',
          boxShadow: '0 0 10px rgba(244, 63, 94, 0.4)',
        }} />
      <div className="absolute inset-0 flex items-center justify-between px-2">
        <span className="text-mono text-[0.5rem]" style={{ color: 'var(--text-muted)' }}>0&deg;</span>
        <span className="text-mono text-[0.5rem]" style={{ color: 'rgba(34, 197, 94, 0.5)' }}>OPTIMAL</span>
        <span className="text-mono text-[0.5rem]" style={{ color: 'var(--text-muted)' }}>80&deg;</span>
      </div>
    </div>
  )
}

function ShotDetailsTable({ shots }: { shots: { shot_id: number; shot_type: string; made: boolean; distance: number; release_angle: number; entry_angle?: number; confidence?: number; shot_speed?: number; flight_time?: number; arc_height?: number }[] }) {

  return (
    <div className="overflow-x-auto">
      <table className="w-full">
        <thead>
          <tr style={{ borderBottom: '1px solid rgba(249, 115, 22, 0.08)' }}>
            {['#', 'Type', 'Result', 'Dist', 'Angle', 'Speed', 'Flight', 'Arc'].map(h => (
              <th key={h} className="text-left py-3 px-3 text-[0.55rem] font-bold tracking-[0.12em] uppercase"
                style={{ color: 'var(--text-muted)' }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {shots.map((shot, idx) => (
            <tr key={shot.shot_id}
              className="transition-colors"
              style={{
                borderBottom: '1px solid rgba(255, 255, 255, 0.02)',
                animation: `fadeInUp 0.3s ease-out ${idx * 25}ms backwards`,
              }}
              onMouseEnter={(e) => e.currentTarget.style.background = 'rgba(249, 115, 22, 0.03)'}
              onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}
            >
              <td className="py-2.5 px-3 text-mono text-xs" style={{ color: 'var(--text-muted)' }}>
                {String(shot.shot_id).padStart(2, '0')}
              </td>
              <td className="py-2.5 px-3">
                <span className="badge" style={{
                  background: `${TYPE_COLORS_VAR[shot.shot_type] || 'var(--text-muted)'}12`,
                  color: TYPE_COLORS_VAR[shot.shot_type] || 'var(--text-muted)',
                  border: `1px solid ${TYPE_COLORS_VAR[shot.shot_type] || 'var(--text-muted)'}25`,
                }}>
                  {TYPE_LABELS[shot.shot_type] || shot.shot_type}
                </span>
              </td>
              <td className="py-2.5 px-3">
                <span className={`badge ${shot.made ? 'badge-success' : 'badge-error'}`}>
                  {shot.made ? 'MADE' : 'MISS'}
                </span>
              </td>
              <td className="py-2.5 px-3 text-mono text-xs" style={{ color: 'var(--neon-cyan)' }}>
                {shot.distance.toFixed(1)}<span style={{ color: 'var(--text-muted)' }}>m</span>
              </td>
              <td className="py-2.5 px-3 text-mono text-xs" style={{ color: 'var(--text-primary)' }}>
                {shot.release_angle.toFixed(1)}<span style={{ color: 'var(--text-muted)' }}>&deg;</span>
              </td>
              <td className="py-2.5 px-3 text-mono text-xs" style={{ color: 'var(--neon-green)' }}>
                {shot.shot_speed?.toFixed(1) || '—'}<span style={{ color: 'var(--text-muted)' }}>m/s</span>
              </td>
              <td className="py-2.5 px-3 text-mono text-xs" style={{ color: 'var(--orange-400)' }}>
                {shot.flight_time?.toFixed(2) || '—'}<span style={{ color: 'var(--text-muted)' }}>s</span>
              </td>
              <td className="py-2.5 px-3 text-mono text-xs" style={{ color: 'var(--neon-pink)' }}>
                {shot.arc_height?.toFixed(2) || '—'}<span style={{ color: 'var(--text-muted)' }}>m</span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {shots.length === 0 && (
        <div className="text-center py-12">
          <Flame size={32} style={{ color: 'var(--text-muted)', margin: '0 auto 0.75rem' }} />
          <p className="text-display text-base tracking-wider mb-1" style={{ color: 'var(--text-muted)' }}>NO SHOTS DETECTED</p>
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>Try a different video with clearer shooting</p>
        </div>
      )}
    </div>
  )
}

