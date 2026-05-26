import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts'

interface DistanceChartProps {
  data: Record<string, number>
}

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ value: number }>; label?: string }) => {
  if (!active || !payload?.length) return null
  return (
    <div className="px-3 py-2 rounded-lg" style={{
      background: 'rgba(7, 8, 13, 0.95)',
      border: '1px solid rgba(0, 229, 255, 0.15)',
      backdropFilter: 'blur(8px)',
      boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
    }}>
      <p className="text-mono text-xs font-bold" style={{ color: 'var(--neon-cyan)' }}>{label}</p>
      <p className="text-mono text-sm font-bold" style={{ color: 'var(--text-bright)' }}>
        {payload[0].value} <span style={{ color: 'var(--text-muted)', fontSize: '0.65rem' }}>shots</span>
      </p>
    </div>
  )
}

export default function DistanceChart({ data }: DistanceChartProps) {
  const entries = Object.entries(data).map(([bin, count]) => ({
    bin,
    count,
    label: bin.replace('m', '').replace('+', '+'),
  }))

  const maxCount = Math.max(...entries.map(e => e.count), 1)

  return (
    <div style={{ width: '100%', height: 220 }}>
      <ResponsiveContainer>
        <BarChart data={entries} margin={{ top: 8, right: 8, bottom: 4, left: -20 }}>
          <XAxis
            dataKey="label"
            tick={{ fill: '#3e4760', fontSize: 10, fontFamily: 'JetBrains Mono, monospace' }}
            axisLine={{ stroke: 'rgba(249, 115, 22, 0.06)' }}
            tickLine={false}
          />
          <YAxis
            tick={{ fill: '#3e4760', fontSize: 10, fontFamily: 'JetBrains Mono, monospace' }}
            axisLine={false}
            tickLine={false}
            allowDecimals={false}
          />
          <Tooltip content={<CustomTooltip />} cursor={{ fill: 'rgba(0, 229, 255, 0.04)' }} />
          <Bar dataKey="count" radius={[4, 4, 0, 0]} maxBarSize={40}>
            {entries.map((entry, idx) => (
              <Cell
                key={idx}
                fill={entry.count === maxCount
                  ? 'rgba(0, 229, 255, 0.75)'
                  : 'rgba(0, 229, 255, 0.25)'}
                style={{
                  filter: entry.count === maxCount ? 'drop-shadow(0 0 6px rgba(0, 229, 255, 0.3))' : 'none',
                  transition: 'all 0.3s ease',
                }}
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
