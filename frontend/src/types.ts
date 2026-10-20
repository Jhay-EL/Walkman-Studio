export interface WalkmanDrive {
  id: string;
  name: string;
  mount_point: string;
  type: 'internal' | 'microsd' | 'virtual';
  total_bytes: number;
  used_bytes: number;
  free_bytes: number;
  percent_used: number;
  has_cfw: boolean;
  music_dir: string;
}

export interface Track {
  filename: string;
  relative_path: string;
  full_path: string;
  format: string; // FLAC | MP3
  title: string;
  artist: string;
  album: string;
  track_num: string;
  year: string;
  genre: string;
  duration_seconds: number;
  bitrate_kbps: number;
  sample_rate: number;
  bits_per_sample: number;
  has_artwork: boolean;
  size_bytes: number;
}

export interface LibraryData {
  tracks: Track[];
  albums: string[];
  artists: string[];
  total_tracks: number;
}

export interface Playlist {
  name: string;
  filename: string;
  track_count: number;
  tracks: string[];
  full_path: string;
}

export interface CfwSettings {
  has_cfw: boolean;
  raw_text: string;
  parsed: Record<string, string>;
}

export interface TransferQueueItem {
  id: string;
  path: string;
  filename: string;
  status: 'pending' | 'converting' | 'success' | 'error';
  targetPath?: string;
  error?: string;
}
