import axios from 'axios';
import { WalkmanDrive, LibraryData, Playlist, CfwSettings } from './types';

const API_BASE = '/api';

export const api = {
  async getDrives(allowVirtual = false): Promise<WalkmanDrive[]> {
    const res = await axios.get<{ drives: WalkmanDrive[] }>(`${API_BASE}/drives`, {
      params: { allow_virtual: allowVirtual },
    });
    return res.data.drives;
  },

  async initVirtual(): Promise<void> {
    await axios.post(`${API_BASE}/drives/virtual/init`);
  },

  async getLibrary(mountPoint: string): Promise<LibraryData> {
    const res = await axios.get<LibraryData>(`${API_BASE}/library`, {
      params: { mount_point: mountPoint },
    });
    return res.data;
  },

  getArtworkUrl(filePath: string): string {
    return `${API_BASE}/artwork?file_path=${encodeURIComponent(filePath)}`;
  },

  async transferFiles(payload: {
    source_files: string[];
    target_mount: string;
    preset: string;
    custom_artist?: string;
    custom_album?: string;
  }) {
    const res = await axios.post(`${API_BASE}/transfer`, payload);
    return res.data;
  },

  async updateMetadata(formData: FormData) {
    const res = await axios.put(`${API_BASE}/metadata`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    return res.data;
  },

  async validateArtwork(coverFile: File) {
    const formData = new FormData();
    formData.append('cover_file', coverFile);
    const res = await axios.post<{ valid: boolean; message: string }>(`${API_BASE}/validate-artwork`, formData);
    return res.data;
  },

  async getPlaylists(mountPoint: string): Promise<Playlist[]> {
    const res = await axios.get<{ playlists: Playlist[] }>(`${API_BASE}/playlists`, {
      params: { mount_point: mountPoint },
    });
    return res.data.playlists;
  },

  async createPlaylist(mountPoint: string, name: string, relativeTracks: string[]) {
    const res = await axios.post(`${API_BASE}/playlists`, {
      mount_point: mountPoint,
      playlist_name: name,
      relative_tracks: relativeTracks,
    });
    return res.data;
  },

  async deletePlaylist(mountPoint: string, name: string) {
    const res = await axios.delete(`${API_BASE}/playlists`, {
      params: { mount_point: mountPoint, playlist_name: name },
    });
    return res.data;
  },

  async getCfw(mountPoint: string): Promise<CfwSettings> {
    const res = await axios.get<CfwSettings>(`${API_BASE}/cfw-dsp`, {
      params: { mount_point: mountPoint },
    });
    return res.data;
  },

  async saveCfw(mountPoint: string, settings: Record<string, string>, rawOverride?: string) {
    const res = await axios.post(`${API_BASE}/cfw-dsp`, {
      mount_point: mountPoint,
      settings,
      raw_override: rawOverride,
    });
    return res.data;
  },

  async cleanAndEject(mountPoint: string) {
    const res = await axios.post(`${API_BASE}/clean-eject`, {
      mount_point: mountPoint,
    });
    return res.data;
  },
};
