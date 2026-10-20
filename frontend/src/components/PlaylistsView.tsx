import React, { useState } from 'react';
import { ListMusic, Plus, Trash2, ArrowUp, ArrowDown, Save, Music } from 'lucide-react';
import { Playlist, Track, WalkmanDrive } from '../types';
import { api } from '../api';

interface Props {
  activeDrive: WalkmanDrive | null;
  playlists: Playlist[];
  libraryTracks: Track[];
  onRefreshPlaylists: () => void;
}

export const PlaylistsView: React.FC<Props> = ({
  activeDrive,
  playlists,
  libraryTracks,
  onRefreshPlaylists,
}) => {
  const [selectedPlaylist, setSelectedPlaylist] = useState<Playlist | null>(null);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [currentTracks, setCurrentTracks] = useState<string[]>([]);
  const [isSaving, setIsSaving] = useState(false);

  const handleSelectPlaylist = (pl: Playlist) => {
    setSelectedPlaylist(pl);
    setCurrentTracks([...pl.tracks]);
  };

  const handleCreateNew = () => {
    setSelectedPlaylist({
      name: 'New Playlist.m3u8',
      filename: 'New Playlist.m3u8',
      track_count: 0,
      tracks: [],
      full_path: '',
    });
    setNewPlaylistName('My Heavy Rotation');
    setCurrentTracks([]);
  };

  const handleMove = (index: number, direction: 'up' | 'down') => {
    const targetIdx = direction === 'up' ? index - 1 : index + 1;
    if (targetIdx < 0 || targetIdx >= currentTracks.length) return;

    const updated = [...currentTracks];
    const [moved] = updated.splice(index, 1);
    updated.splice(targetIdx, 0, moved);
    setCurrentTracks(updated);
  };

  const handleRemoveTrack = (index: number) => {
    setCurrentTracks((prev) => prev.filter((_, i) => i !== index));
  };

  const handleAddTrackFromLibrary = (track: Track) => {
    if (!currentTracks.includes(track.relative_path)) {
      setCurrentTracks((prev) => [...prev, track.relative_path]);
    }
  };

  const handleSavePlaylist = async () => {
    if (!activeDrive) return;
    const name = selectedPlaylist?.full_path
      ? selectedPlaylist.name
      : newPlaylistName.trim();
    if (!name) {
      alert('Please enter a playlist name');
      return;
    }

    setIsSaving(true);
    try {
      await api.createPlaylist(activeDrive.mount_point, name, currentTracks);
      onRefreshPlaylists();
      alert(`Playlist "${name}" saved to /MUSIC/ with CRLF line endings.`);
    } catch (e: any) {
      alert(`Failed saving playlist: ${e.message}`);
    } finally {
      setIsSaving(false);
    }
  };

  const handleDeletePlaylist = async (pl: Playlist) => {
    if (!activeDrive) return;
    if (!confirm(`Delete playlist ${pl.name}?`)) return;

    try {
      await api.deletePlaylist(activeDrive.mount_point, pl.filename);
      if (selectedPlaylist?.filename === pl.filename) {
        setSelectedPlaylist(null);
        setCurrentTracks([]);
      }
      onRefreshPlaylists();
    } catch (e: any) {
      alert(`Delete error: ${e.message}`);
    }
  };

  return (
    <div className="p-6 max-w-7xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-semibold text-white">Playlists (.M3U8)</h2>
          <p className="text-xs text-zinc-400">
            Stored in <span className="font-mono text-zinc-300">/MUSIC/</span> with relative POSIX paths & hardware-mandated CRLF line endings.
          </p>
        </div>

        <button
          onClick={handleCreateNew}
          className="px-3.5 py-1.5 rounded-lg bg-gradient-to-r from-amber-500 to-yellow-600 hover:from-amber-400 hover:to-yellow-500 text-black text-xs font-semibold shadow-md flex items-center space-x-1.5 transition-all active:scale-95"
        >
          <Plus className="w-4 h-4" />
          <span>New Playlist</span>
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Playlists Left List */}
        <div className="bg-walkman-card border border-walkman-border rounded-xl p-4 space-y-3">
          <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider block">
            Drive Playlists ({playlists.length})
          </label>

          {playlists.length === 0 ? (
            <div className="py-8 text-center text-xs text-zinc-600">
              No playlists found in /MUSIC/
            </div>
          ) : (
            <div className="space-y-1">
              {playlists.map((pl) => (
                <div
                  key={pl.filename}
                  onClick={() => handleSelectPlaylist(pl)}
                  className={`p-2.5 rounded-lg border text-xs cursor-pointer flex items-center justify-between transition-all ${
                    selectedPlaylist?.filename === pl.filename
                      ? 'bg-walkman-hover border-walkman-gold text-walkman-gold shadow-sm font-medium'
                      : 'bg-zinc-900/40 border-walkman-border text-zinc-400 hover:border-zinc-700'
                  }`}
                >
                  <div className="flex items-center space-x-2.5 truncate">
                    <ListMusic className="w-4 h-4 flex-shrink-0" />
                    <span className="truncate">{pl.name}</span>
                  </div>
                  <div className="flex items-center space-x-2 flex-shrink-0">
                    <span className="text-[10px] font-mono text-zinc-500">
                      {pl.track_count} tracks
                    </span>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleDeletePlaylist(pl);
                      }}
                      className="p-1 hover:text-red-400 text-zinc-600"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Playlist Tracks Editor (Center/Right) */}
        <div className="md:col-span-2 bg-walkman-card border border-walkman-border rounded-xl p-5 space-y-4">
          {selectedPlaylist ? (
            <>
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-walkman-border pb-4">
                {!selectedPlaylist.full_path ? (
                  <input
                    type="text"
                    value={newPlaylistName}
                    onChange={(e) => setNewPlaylistName(e.target.value)}
                    placeholder="Enter playlist title..."
                    className="bg-walkman-input border border-walkman-border rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none focus:border-walkman-gold w-64"
                  />
                ) : (
                  <div>
                    <h3 className="text-sm font-semibold text-white">{selectedPlaylist.name}</h3>
                    <p className="text-[11px] text-zinc-500 font-mono">
                      {currentTracks.length} tracks in playlist
                    </p>
                  </div>
                )}

                <button
                  onClick={handleSavePlaylist}
                  disabled={isSaving}
                  className="px-4 py-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-white border border-zinc-700 text-xs font-medium flex items-center space-x-2 shadow-sm transition-all"
                >
                  <Save className="w-3.5 h-3.5 text-walkman-gold" />
                  <span>{isSaving ? 'Writing...' : 'Save Playlist (CRLF)'}</span>
                </button>
              </div>

              {/* Tracks List */}
              <div className="space-y-1.5 max-h-72 overflow-y-auto pr-1">
                {currentTracks.length === 0 ? (
                  <div className="py-12 text-center text-xs text-zinc-600">
                    Playlist is empty. Add songs from your library below.
                  </div>
                ) : (
                  currentTracks.map((trk, idx) => (
                    <div
                      key={`${trk}-${idx}`}
                      className="p-2 bg-zinc-900/60 border border-zinc-800 rounded-lg flex items-center justify-between text-xs text-zinc-300"
                    >
                      <div className="flex items-center space-x-2 truncate">
                        <span className="font-mono text-[10px] text-zinc-500 w-5 text-right">
                          {idx + 1}
                        </span>
                        <span className="truncate font-medium">{trk}</span>
                      </div>
                      <div className="flex items-center space-x-1 flex-shrink-0">
                        <button
                          onClick={() => handleMove(idx, 'up')}
                          disabled={idx === 0}
                          className="p-1 text-zinc-500 hover:text-white disabled:opacity-20"
                        >
                          <ArrowUp className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => handleMove(idx, 'down')}
                          disabled={idx === currentTracks.length - 1}
                          className="p-1 text-zinc-500 hover:text-white disabled:opacity-20"
                        >
                          <ArrowDown className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => handleRemoveTrack(idx)}
                          className="p-1 text-zinc-600 hover:text-red-400"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </div>
                  ))
                )}
              </div>

              {/* Quick Add from Library */}
              <div className="border-t border-walkman-border pt-4">
                <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-2 block">
                  Add From Library ({libraryTracks.length} available)
                </label>
                <div className="max-h-40 overflow-y-auto space-y-1 pr-1">
                  {libraryTracks.slice(0, 50).map((t) => (
                    <div
                      key={t.full_path}
                      onClick={() => handleAddTrackFromLibrary(t)}
                      className="p-1.5 rounded hover:bg-zinc-800/60 cursor-pointer flex items-center justify-between text-[11px] text-zinc-400 hover:text-white transition-colors"
                    >
                      <span className="truncate">
                        {t.artist} - {t.title}
                      </span>
                      <Plus className="w-3.5 h-3.5 text-zinc-600 hover:text-walkman-gold flex-shrink-0" />
                    </div>
                  ))}
                </div>
              </div>
            </>
          ) : (
            <div className="py-20 text-center text-zinc-600 text-xs">
              Select or create a playlist on the left.
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
