export interface AnalysisResult {
  task_id: string
  status: string
  summary: {
    total_shots: number
    made_shots: number
    overall_percentage: number
    average_distance: number
    video_duration: number
  }
  by_type: Record<string, ShotTypeStats>
  by_zone: Record<string, ZoneStats>
  distance_distribution: Record<string, number>
  streaks: {
    max_made_streak: number
    max_missed_streak: number
  }
  angles: {
    avg_release_angle: number
    std_release_angle: number
    min_release_angle: number
    max_release_angle: number
  }
  kinematics?: {
    avg_speed: number
    avg_flight_time: number
    avg_arc_height: number
  }
  shot_locations: ShotLocation[]
  shots: ShotDetail[]
  annotated_video?: string
}

export interface ShotTypeStats {
  attempts: number
  made: number
  percentage: number
  avg_distance: number
}

export interface ZoneStats {
  attempts: number
  made: number
  percentage: number
}

export interface ShotLocation {
  x: number
  y: number
  made: boolean
  type: string
  distance: number
}

export interface ShotDetail {
  shot_id: number
  shot_type: string
  made: boolean
  distance: number
  release_angle: number
  entry_angle: number
  confidence?: number
  trajectory_points?: [number, number][]
  flight_time?: number
  shot_speed?: number
  arc_height?: number
}
