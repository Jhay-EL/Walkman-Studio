import React, { useState, useMemo } from 'react';
import { Search, Music, ChevronLeft, ChevronRight, Edit3, Image as ImageIcon } from 'lucide-react';
import { Track } from '../types';
import { api } from '../api';

interface Props {
  tracks: Track[];
  loading: boolean;
  onEditTrack: (track: Track) => void;
  onGoToTransfer: () => void;
}

const PAGE_SIZE = 50;

export const LibraryView: React.FC<Props> = ({
  tracks,
  loading,
  onEditTrack,
  onGoToTransfer,
}) => {
  const [search, setSearch] = useState('');
  const [formatFilter, setFormatFilter] = useState<'ALL' | 'FLAC' | 'MP3' | 'OTHER'>('ALL');
  const [currentPage, setCurrentPage] = useState(1);

  // Filtered tracks list
  const filteredTracks = useMemo(() => {
    return tracks.filter((t) => {
      const q = search.toLowerCase();
      const matchesSearch =
        !q ||
        t.title.toLowerCase().includes(q) ||
        t.artist.toLowerCase().includes(q) ||
        t.album.toLowerCase().includes(q);

      if (!matchesSearch) return false;

      if (formatFilter === 'ALL') return true;
      if (formatFilter === 'OTHER') return t.format !== 'FLAC' && t.format !== 'MP3';
      return t.format === formatFilter;
    });
  }, [tracks, search, formatFilter]);

  // Total pages and paginated slice
  const totalPages = Math.max(1, Math.ceil(filteredTracks.length / PAGE_SIZE));
  const validPage = Math.min(currentPage, totalPages);

  const paginatedTracks = useMemo(() => {
    const start = (validPage - 1) * PAGE_SIZE;
    return filteredTracks.slice(start, start + PAGE_SIZE);
  }, [filteredTracks, validPage]);

  const handleSearchChange = (val: string) => {
    setSearch(val);
    setCurrentPage(1);
  };

  const handleFilterChange = (fmt: 'ALL' | 'FLAC' | 'MP3' | 'OTHER') => {
    setFormatFilter(fmt);
    setCurrentPage(1);
  };

  const formatDuration = (seconds: number) => {
    if (!seconds || seconds <= 0) return '--:--';
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  };

  return (
    <div className="p-6 space-y-5 max-w-7xl mx-auto">
      {/* Search & Filter Header */}
      <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
        {/* Search Input & Total Counter */}
        <div className="flex items-center space-x-3 w-full sm:w-auto">
          <div className="relative w-full sm:w-80">
            <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-zinc-500" />
            <input
              type="text"
              value={search}
              onChange={(e) => handleSearchChange(e.target.value)}
              placeholder="Search 7,000+ tracks, artists, albums..."
              className="w-full pl-10 pr-4 py-2 bg-walkman-input border border-walkman-border rounded-lg text-xs text-white placeholder-zinc-500 focus:outline-none focus:border-walkman-gold transition-colors"
            />
          </div>
          <span className="hidden md:inline-block px-2.5 py-1 rounded bg-zinc-900 border border-zinc-800 text-[11px] font-mono text-zinc-400">
            {filteredTracks.length.toLocaleString()} tracks
          </span>
        </div>

        {/* Format Filter Badges */}
        <div className="flex items-center space-x-2">
          {(['ALL', 'FLAC', 'MP3', 'OTHER'] as const).map((fmt) => (
            <button
              key={fmt}
              onClick={() => handleFilterChange(fmt)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                formatFilter === fmt
                  ? 'bg-walkman-hover text-walkman-gold border border-walkman-gold/50 shadow-sm font-semibold'
                  : 'bg-zinc-900 border border-walkman-border text-zinc-400 hover:text-white'
              }`}
            >
              {fmt}
            </button>
          ))}
        </div>
      </div>

      {/* Tracks Table / Empty State */}
      {loading ? (
        <div className="py-24 text-center text-zinc-500">
          <div className="w-8 h-8 border-2 border-walkman-gold border-t-transparent rounded-full animate-spin mx-auto mb-3" />
          <p className="text-sm">Scanning Walkman library...</p>
        </div>
      ) : filteredTracks.length === 0 ? (
        <div className="py-24 text-center border border-dashed border-zinc-800 rounded-2xl bg-zinc-900/20">
          <Music className="w-12 h-12 text-zinc-700 mx-auto mb-3" />
          <h3 className="text-base font-medium text-white mb-1">No Music Found</h3>
          <p className="text-xs text-zinc-500 max-w-sm mx-auto mb-4">
            {tracks.length === 0
              ? 'This drive has no music in /MUSIC/ yet. Transfer or convert your audio files now.'
              : 'No tracks match your current filter.'}
          </p>
          {tracks.length === 0 && (
            <button
              onClick={onGoToTransfer}
              className="px-4 py-2 rounded-lg bg-gradient-to-r from-amber-500 to-yellow-600 hover:from-amber-400 hover:to-yellow-500 text-black text-xs font-semibold shadow-md transition-all active:scale-95"
            >
              Transfer Music to Walkman
            </button>
          )}
        </div>
      ) : (
        <div className="bg-walkman-card border border-walkman-border rounded-xl overflow-hidden shadow-sm">
          <table className="w-full text-left text-xs text-zinc-300">
            <thead className="bg-zinc-900/80 text-zinc-400 text-[11px] uppercase tracking-wider border-b border-walkman-border font-medium">
              <tr>
                <th className="py-3 px-4 w-14 text-center">#</th>
                <th className="py-3 px-3 w-12">Cover</th>
                <th className="py-3 px-4">Title & Artist</th>
                <th className="py-3 px-4 hidden md:table-cell">Album</th>
                <th className="py-3 px-4 w-28 text-center">Audio Spec</th>
                <th className="py-3 px-4 w-20 text-right">Time</th>
                <th className="py-3 px-4 w-16 text-center">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800/50">
              {paginatedTracks.map((track, idx) => {
                const globalIndex = (validPage - 1) * PAGE_SIZE + idx + 1;
                const isHiRes =
                  track.format === 'FLAC' &&
                  (track.bits_per_sample >= 24 || track.sample_rate >= 96000);

                return (
                  <tr
                    key={track.full_path}
                    className="hover:bg-walkman-hover/50 transition-colors group"
                  >
                    <td className="py-3 px-4 text-center font-mono text-zinc-500 text-[11px]">
                      {track.track_num ? track.track_num : globalIndex}
                    </td>

                    {/* Artwork Thumbnail */}
                    <td className="py-2 px-3">
                      <div className="w-9 h-9 rounded bg-zinc-900 border border-zinc-800 flex items-center justify-center overflow-hidden flex-shrink-0">
                        {track.has_artwork ? (
                          <img
                            src={api.getArtworkUrl(track.full_path)}
                            alt="Cover"
                            loading="lazy"
                            className="w-full h-full object-cover"
                            onError={(e) => {
                              (e.target as HTMLElement).style.display = 'none';
                            }}
                          />
                        ) : (
                          <ImageIcon className="w-4 h-4 text-zinc-600" />
                        )}
                      </div>
                    </td>

                    {/* Title & Artist */}
                    <td className="py-3 px-4">
                      <div className="font-medium text-white group-hover:text-walkman-gold transition-colors truncate max-w-xs md:max-w-md">
                        {track.title}
                      </div>
                      <div className="text-[11px] text-zinc-400 truncate max-w-xs md:max-w-md">
                        {track.artist}
                      </div>
                    </td>

                    {/* Album */}
                    <td className="py-3 px-4 text-zinc-400 hidden md:table-cell truncate max-w-xs">
                      {track.album}
                    </td>

                    {/* Format / Spec Badge */}
                    <td className="py-3 px-4 text-center">
                      <div className="flex flex-col items-center">
                        <span
                          className={`px-1.5 py-0.5 rounded text-[10px] font-mono font-medium ${
                            isHiRes
                              ? 'bg-amber-500/10 text-walkman-gold border border-amber-500/30'
                              : track.format === 'FLAC'
                              ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                              : 'bg-zinc-800 text-zinc-400'
                          }`}
                        >
                          {isHiRes ? 'Hi-Res FLAC' : track.format}
                        </span>
                        <span className="text-[9px] font-mono text-zinc-500 mt-0.5">
                          {track.format === 'FLAC' && track.sample_rate
                            ? `${track.bits_per_sample || 16}b/${(track.sample_rate / 1000).toFixed(1)}k`
                            : track.bitrate_kbps > 0
                            ? `${track.bitrate_kbps} kbps`
                            : 'Audio'}
                        </span>
                      </div>
                    </td>

                    {/* Duration */}
                    <td className="py-3 px-4 text-right font-mono text-zinc-400 text-xs">
                      {formatDuration(track.duration_seconds)}
                    </td>

                    {/* Actions */}
                    <td className="py-3 px-4 text-center">
                      <button
                        onClick={() => onEditTrack(track)}
                        title="Edit Tags & Artwork"
                        className="p-1.5 rounded hover:bg-zinc-800 text-zinc-500 hover:text-walkman-gold transition-colors"
                      >
                        <Edit3 className="w-3.5 h-3.5" />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>

          {/* Pagination Controls */}
          <div className="p-3 bg-zinc-900/60 border-t border-walkman-border flex items-center justify-between text-xs text-zinc-400">
            <span className="font-mono text-[11px]">
              Showing {((validPage - 1) * PAGE_SIZE) + 1}–{Math.min(validPage * PAGE_SIZE, filteredTracks.length)} of {filteredTracks.length.toLocaleString()} tracks
            </span>

            <div className="flex items-center space-x-2">
              <button
                onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
                disabled={validPage <= 1}
                className="px-2.5 py-1 rounded bg-zinc-800 hover:bg-zinc-700 disabled:opacity-30 disabled:hover:bg-zinc-800 flex items-center space-x-1 text-white transition-colors"
              >
                <ChevronLeft className="w-3.5 h-3.5" />
                <span>Prev</span>
              </button>

              <span className="px-3 py-1 font-mono text-zinc-300">
                Page <strong className="text-walkman-gold">{validPage}</strong> of {totalPages}
              </span>

              <button
                onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
                disabled={validPage >= totalPages}
                className="px-2.5 py-1 rounded bg-zinc-800 hover:bg-zinc-700 disabled:opacity-30 disabled:hover:bg-zinc-800 flex items-center space-x-1 text-white transition-colors"
              >
                <span>Next</span>
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
