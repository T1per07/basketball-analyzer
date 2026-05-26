import { Flame, Snowflake } from 'lucide-react'

interface StreakDisplayProps {
  maxMadeStreak: number
  maxMissedStreak: number
}

export default function StreakDisplay({ maxMadeStreak, maxMissedStreak }: StreakDisplayProps) {
  return (
    <div className="grid grid-cols-2 gap-4">
      <StreakCard
        icon={<Flame className="w-5 h-5" />}
        label="Hot Streak"
        value={maxMadeStreak}
        unit="in a row"
        color="var(--orange-500)"
        glow="rgba(249, 115, 22, 0.08)"
      />
      <StreakCard
        icon={<Snowflake className="w-5 h-5" />}
        label="Cold Streak"
        value={maxMissedStreak}
        unit="in a row"
        color="var(--neon-cyan)"
        glow="rgba(0, 229, 255, 0.06)"
      />
    </div>
  )
}

function StreakCard({ icon, label, value, unit, color, glow }: {
  icon: React.ReactNode; label: string; value: number; unit: string; color: string; glow: string
}) {
  return (
    <div className="relative overflow-hidden rounded-xl p-4 text-center"
      style={{
        background: `linear-gradient(135deg, ${glow}, var(--surface-card))`,
        border: `1px solid ${color}20`,
        boxShadow: 'var(--shadow-card)',
      }}>
      <div className="flex items-center justify-center gap-2 mb-2" style={{ color }}>
        {icon}
        <span className="text-display text-[0.6rem] font-bold tracking-[0.12em] uppercase">{label}</span>
      </div>
      <div className="text-display text-3xl font-black mb-1" style={{ color }}>
        {value}
      </div>
      <span className="text-[0.6rem] font-semibold tracking-wider" style={{ color: 'var(--text-muted)' }}>{unit}</span>
    </div>
  )
}
