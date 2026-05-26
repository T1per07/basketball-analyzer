import type { ZoneStats } from '../types'

interface ZoneHeatmapProps {
  data: Record<string, ZoneStats>
}

const ZONE_LABELS: Record<string, string> = {
  paint: 'PAINT',
  mid_range_left: 'MID-L',
  mid_range_right: 'MID-R',
  three_point_left: '3PT-L',
  three_point_right: '3PT-R',
  three_point_top: '3PT-T',
  corner_three_left: 'CNR-L',
  corner_three_right: 'CNR-R',
}

const ZONE_POSITIONS: Record<string, { x: number; y: number; w: number; h: number }> = {
  paint:                { x: 0.38, y: 0.55, w: 0.24, h: 0.35 },
  mid_range_left:       { x: 0.15, y: 0.50, w: 0.20, h: 0.30 },
  mid_range_right:      { x: 0.65, y: 0.50, w: 0.20, h: 0.30 },
  three_point_left:     { x: 0.05, y: 0.30, w: 0.18, h: 0.25 },
  three_point_right:    { x: 0.77, y: 0.30, w: 0.18, h: 0.25 },
  three_point_top:      { x: 0.25, y: 0.10, w: 0.50, h: 0.22 },
  corner_three_left:    { x: 0.02, y: 0.55, w: 0.12, h: 0.35 },
  corner_three_right:   { x: 0.86, y: 0.55, w: 0.12, h: 0.35 },
}

function getZoneColor(pct: number, attempts: number): string {
  if (attempts === 0) return 'rgba(22, 26, 39, 0.6)'
  if (pct >= 0.6) return 'rgba(34, 197, 94, 0.3)'
  if (pct >= 0.45) return 'rgba(0, 229, 255, 0.25)'
  if (pct >= 0.3) return 'rgba(251, 191, 36, 0.2)'
  return 'rgba(244, 63, 94, 0.25)'
}

function getZoneBorder(pct: number, attempts: number): string {
  if (attempts === 0) return 'rgba(62, 71, 96, 0.25)'
  if (pct >= 0.6) return 'rgba(34, 197, 94, 0.45)'
  if (pct >= 0.45) return 'rgba(0, 229, 255, 0.35)'
  if (pct >= 0.3) return 'rgba(251, 191, 36, 0.35)'
  return 'rgba(244, 63, 94, 0.35)'
}

export default function ZoneHeatmap({ data }: ZoneHeatmapProps) {
  return (
    <div className="relative w-full" style={{ aspectRatio: '500 / 470' }}>
      <svg viewBox="0 0 500 470" className="absolute inset-0 w-full h-full">
        {/* Court background */}
        <rect x="10" y="10" width="480" height="450" rx="8"
          fill="rgba(16, 19, 28, 0.8)" stroke="rgba(249, 115, 22, 0.08)" strokeWidth="1.5" />

        {/* Court lines */}
        <rect x="30" y="30" width="440" height="410" rx="4"
          fill="none" stroke="rgba(249, 115, 22, 0.08)" strokeWidth="1" />

        {/* Half court line */}
        <line x1="30" y1="235" x2="470" y2="235"
          stroke="rgba(249, 115, 22, 0.06)" strokeWidth="1" strokeDasharray="6 4" />

        {/* Center circle */}
        <circle cx="250" cy="235" r="40"
          fill="none" stroke="rgba(249, 115, 22, 0.06)" strokeWidth="1" />

        {/* Basket area */}
        <rect x="175" y="340" width="150" height="100" rx="2"
          fill="none" stroke="rgba(249, 115, 22, 0.15)" strokeWidth="1" />

        {/* Free throw circle */}
        <circle cx="250" cy="340" r="40"
          fill="none" stroke="rgba(249, 115, 22, 0.06)" strokeWidth="1" />

        {/* Backboard */}
        <line x1="210" y1="420" x2="290" y2="420"
          stroke="rgba(249, 115, 22, 0.35)" strokeWidth="2.5" />

        {/* Hoop */}
        <circle cx="250" cy="430" r="8"
          fill="none" stroke="rgba(249, 115, 22, 0.45)" strokeWidth="2" />

        {/* 3-point arc */}
        <path d="M 70 440 L 70 280 A 180 180 0 0 1 430 280 L 430 440"
          fill="none" stroke="rgba(249, 115, 22, 0.06)" strokeWidth="1" strokeDasharray="8 4" />

        {/* Zone rectangles */}
        {Object.entries(ZONE_POSITIONS).map(([zone, pos]) => {
          const stats = data[zone]
          const pct = stats?.percentage ?? 0
          const attempts = stats?.attempts ?? 0
          const made = stats?.made ?? 0

          const px = pos.x * 440 + 30
          const py = pos.y * 410 + 30
          const pw = pos.w * 440
          const ph = pos.h * 410

          return (
            <g key={zone}>
              <rect
                x={px} y={py} width={pw} height={ph} rx="4"
                fill={getZoneColor(pct, attempts)}
                stroke={getZoneBorder(pct, attempts)}
                strokeWidth="1"
                style={{ transition: 'all 0.3s ease' }}
              />
              <text
                x={px + pw / 2} y={py + ph / 2 - 8}
                textAnchor="middle"
                fill="rgba(241, 245, 249, 0.75)"
                fontSize="10"
                fontFamily="Orbitron, sans-serif"
                fontWeight="700"
                letterSpacing="1"
              >
                {ZONE_LABELS[zone]}
              </text>
              {attempts > 0 && (
                <>
                  <text
                    x={px + pw / 2} y={py + ph / 2 + 8}
                    textAnchor="middle"
                    fill="rgba(0, 229, 255, 0.85)"
                    fontSize="13"
                    fontFamily="JetBrains Mono, monospace"
                    fontWeight="700"
                  >
                    {(pct * 100).toFixed(0)}%
                  </text>
                  <text
                    x={px + pw / 2} y={py + ph / 2 + 22}
                    textAnchor="middle"
                    fill="rgba(100, 116, 139, 0.6)"
                    fontSize="8"
                    fontFamily="JetBrains Mono, monospace"
                  >
                    {made}/{attempts}
                  </text>
                </>
              )}
            </g>
          )
        })}
      </svg>

      {/* Legend */}
      <div className="absolute bottom-2 right-2 flex items-center gap-3 px-3 py-1.5 rounded-lg"
        style={{ background: 'rgba(7, 8, 13, 0.85)', border: '1px solid rgba(249, 115, 22, 0.08)' }}>
        {[
          { label: '60%+', color: 'rgba(34, 197, 94, 0.5)' },
          { label: '45%+', color: 'rgba(0, 229, 255, 0.5)' },
          { label: '30%+', color: 'rgba(251, 191, 36, 0.5)' },
          { label: '<30%', color: 'rgba(244, 63, 94, 0.5)' },
        ].map(item => (
          <div key={item.label} className="flex items-center gap-1">
            <div className="w-2.5 h-2.5 rounded-sm" style={{ background: item.color }} />
            <span className="text-[0.55rem] font-semibold tracking-wider" style={{ color: 'var(--text-muted)' }}>
              {item.label}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}
