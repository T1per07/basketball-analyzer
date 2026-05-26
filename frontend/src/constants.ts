/** 投篮类型标签映射 */
export const TYPE_LABELS: Record<string, string> = {
  three_point: '3PT',
  mid_range: 'MID',
  layup: 'LAYUP',
  dunk: 'DUNK',
  free_throw: 'FT',
}

/** 投篮类型颜色映射（Hex） */
export const TYPE_COLORS: Record<string, string> = {
  three_point: '#f97316',
  mid_range: '#22c55e',
  layup: '#00e5ff',
  dunk: '#fbbf24',
  free_throw: '#64748b',
}

/** 投篮类型颜色映射（CSS 变量） */
export const TYPE_COLORS_VAR: Record<string, string> = {
  three_point: 'var(--orange-500)',
  mid_range: 'var(--neon-green)',
  layup: 'var(--neon-cyan)',
  dunk: 'var(--neon-gold)',
  free_throw: 'var(--text-secondary)',
}
