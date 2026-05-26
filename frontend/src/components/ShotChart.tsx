import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell, Legend } from 'recharts'
import type { ShotTypeStats } from '../types'
import { TYPE_LABELS, TYPE_COLORS } from '../constants'

interface ShotChartProps {
  data: Record<string, ShotTypeStats>
}

const CustomTooltip = ({ active, payload }: { active?: boolean; payload?: Array<{ payload: Record<string, unknown> }> }) => {
  if (!active || !payload?.length) return null
  const d = payload[0].payload as { name: string; made: number; missed: number; pct: string; avgDist: string }
  return (
    <div className="px-3 py-2 rounded-lg" style={{
      background: 'rgba(7, 8, 13, 0.95)',
      border: '1px solid rgba(249, 115, 22, 0.15)',
      backdropFilter: 'blur(8px)',
      boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
    }}>
      <p className="text-mono text-xs font-bold mb-1" style={{ color: 'var(--orange-400)' }}>{d.name}</p>
      <p className="text-mono text-xs" style={{ color: 'var(--neon-green)' }}>
        Made: {d.made}
      </p>
      <p className="text-mono text-xs" style={{ color: 'var(--neon-pink)' }}>
        Missed: {d.missed}
      </p>
      <p className="text-mono text-xs" style={{ color: 'var(--text-bright)' }}>
        FG%: {d.pct} &middot; Avg: {d.avgDist}m
      </p>
    </div>
  )
}

export default function ShotChart({ data }: ShotChartProps) {
  const entries = Object.entries(data).map(([type, stats]) => ({
    name: TYPE_LABELS[type] || type,
    made: stats.made,
    missed: stats.attempts - stats.made,
    pct: (stats.percentage * 100).toFixed(1),
    avgDist: stats.avg_distance?.toFixed(1) || '—',
    color: TYPE_COLORS[type] || '#64748b',
    attempts: stats.attempts,
  }))

  if (entries.length === 0) {
    return (
      <div className="text-center py-10">
        <p className="text-display text-base tracking-wide mb-1" style={{ color: 'var(--text-muted)' }}>
          NO DATA
        </p>
        <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
          Shot type breakdown will appear after analysis
        </p>
      </div>
    )
  }

  return (
    <div style={{ width: '100%', height: 260 }}>
      <ResponsiveContainer>
        <BarChart
          data={entries}
          layout="vertical"
          margin={{ top: 4, right: 16, bottom: 4, left: 8 }}
          barGap={2}
        >
          <XAxis
            type="number"
            tick={{ fill: '#3e4760', fontSize: 10, fontFamily: 'JetBrains Mono, monospace' }}
            axisLine={{ stroke: 'rgba(249, 115, 22, 0.06)' }}
            tickLine={false}
          />
          <YAxis
            type="category"
            dataKey="name"
            tick={{ fill: '#f1f5f9', fontSize: 11, fontFamily: 'Orbitron, sans-serif', fontWeight: 700 }}
            axisLine={false}
            tickLine={false}
            width={52}
          />
          <Tooltip content={<CustomTooltip />} cursor={{ fill: 'rgba(249, 115, 22, 0.03)' }} />
          <Legend
            wrapperStyle={{ fontSize: '0.6rem', fontFamily: 'Inter, sans-serif' }}
            formatter={(value) => <span style={{ color: '#64748b', fontWeight: 700, letterSpacing: '0.08em' }}>{value}</span>}
          />
          <Bar dataKey="made" name="MADE" stackId="shots" radius={[0, 0, 0, 0]} maxBarSize={28}>
            {entries.map((entry, idx) => (
              <Cell key={idx} fill={entry.color} fillOpacity={0.85} />
            ))}
          </Bar>
          <Bar dataKey="missed" name="MISSED" stackId="shots" radius={[0, 4, 4, 0]} maxBarSize={28}>
            {entries.map((entry, idx) => (
              <Cell key={idx} fill={entry.color} fillOpacity={0.15} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
