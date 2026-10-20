import React, { useState, useEffect } from 'react';
import { Image as ImageIcon, Save, CheckCircle, AlertTriangle, ShieldCheck, Upload } from 'lucide-react';
import { Track } from '../types';
import { api } from '../api';

interface Props {
  selectedTrack: Track | null;
  onSaved: () => void;
}

export const MetadataStudioView: React.FC<Props> = ({ selectedTrack, onSaved }) => {
  const [formData, setFormData] = useState({
    title: '',
    artist: '',
    album: '',
    track_number: '',
    year: '',
    genre: '',
  });

  const [coverFile, setCoverFile] = useState<File | null>(null);
  const [coverPreviewUrl, setCoverPreviewUrl] = useState<string | null>(null);
  const [artworkStatus, setArtworkStatus] = useState<{ valid: boolean; message: string } | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  useEffect(() => {
    if (selectedTrack) {
      setFormData({
        title: selectedTrack.title || '',
        artist: selectedTrack.artist || '',
        album: selectedTrack.album || '',
        track_number: selectedTrack.track_num || '',
        year: selectedTrack.year || '',
        genre: selectedTrack.genre || '',
      });
      setCoverFile(null);
      setCoverPreviewUrl(
        selectedTrack.has_artwork ? api.getArtworkUrl(selectedTrack.full_path) : null
      );
      setArtworkStatus(
        selectedTrack.has_artwork
          ? { valid: true, message: 'Existing Walkman embedded artwork' }
          : null
      );
      setSuccessMsg(null);
    }
  }, [selectedTrack]);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setCoverFile(file);
    const objectUrl = URL.createObjectURL(file);
    setCoverPreviewUrl(objectUrl);

    try {
      const res = await api.validateArtwork(file);
      setArtworkStatus(res);
    } catch {
      setArtworkStatus({
        valid: false,
        message: 'Could not validate image format',
      });
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedTrack) return;

    setIsSaving(true);
    setSuccessMsg(null);

    const body = new FormData();
    body.append('file_path', selectedTrack.full_path);
    body.append('title', formData.title);
    body.append('artist', formData.artist);
    body.append('album', formData.album);
    body.append('track_number', formData.track_number);
    body.append('year', formData.year);
    body.append('genre', formData.genre);

    if (coverFile) {
      body.append('cover_file', coverFile);
    }

    try {
      await api.updateMetadata(body);
      setSuccessMsg('Tags and Baseline JPEG artwork saved successfully!');
      onSaved();
    } catch (err: any) {
      alert(`Save failed: ${err?.response?.data?.detail || err.message}`);
    } finally {
      setIsSaving(false);
    }
  };

  if (!selectedTrack) {
    return (
      <div className="p-12 text-center text-zinc-500 max-w-xl mx-auto my-12 border border-dashed border-zinc-800 rounded-2xl bg-zinc-900/20">
        <ImageIcon className="w-12 h-12 text-zinc-700 mx-auto mb-3" />
        <h3 className="text-base font-medium text-white mb-1">No Track Selected</h3>
        <p className="text-xs text-zinc-500">
          Select an audio track from the <strong className="text-zinc-300">Music Library</strong> tab to view and modify its metadata and Baseline RGB JPEG cover art.
        </p>
      </div>
    );
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      {/* Header Info */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-base font-semibold text-white">Metadata & Artwork Studio</h2>
          <p className="text-xs text-zinc-400 font-mono truncate max-w-xl">
            {selectedTrack.full_path}
          </p>
        </div>

        <div className="flex items-center space-x-2">
          <span className="px-2 py-1 rounded bg-zinc-800 text-[11px] font-mono text-zinc-300 border border-zinc-700">
            {selectedTrack.format === 'MP3' ? 'ID3v2.3 (Strict UTF-16)' : 'FLAC (Vorbis)'}
          </span>
        </div>
      </div>

      <form onSubmit={handleSave} className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Cover Art Box */}
        <div className="bg-walkman-card border border-walkman-border rounded-xl p-5 space-y-4">
          <label className="text-xs font-semibold text-zinc-300 flex items-center justify-between">
            <span>Front Cover Art</span>
            <span className="text-[10px] text-walkman-gold font-mono">Max 800x800 RGB</span>
          </label>

          <div className="w-full aspect-square bg-zinc-900 rounded-lg border-2 border-dashed border-zinc-800 flex items-center justify-center overflow-hidden relative group">
            {coverPreviewUrl ? (
              <img
                src={coverPreviewUrl}
                alt="Album Cover"
                className="w-full h-full object-cover"
              />
            ) : (
              <div className="text-center p-4">
                <ImageIcon className="w-10 h-10 text-zinc-700 mx-auto mb-2" />
                <p className="text-[11px] text-zinc-500">No artwork embedded</p>
              </div>
            )}

            <label className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 flex flex-col items-center justify-center cursor-pointer transition-opacity text-white text-xs font-medium">
              <Upload className="w-6 h-6 mb-1 text-walkman-gold" />
              <span>Replace Artwork</span>
              <input
                type="file"
                accept="image/*"
                onChange={handleFileChange}
                className="hidden"
              />
            </label>
          </div>

          {/* Validation Status Badge */}
          {artworkStatus && (
            <div
              className={`p-2.5 rounded-lg border text-[11px] flex items-start space-x-2 ${
                artworkStatus.valid
                  ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400'
                  : 'bg-amber-500/10 border-amber-500/30 text-amber-300'
              }`}
            >
              {artworkStatus.valid ? (
                <CheckCircle className="w-4 h-4 flex-shrink-0 text-emerald-400 mt-0.5" />
              ) : (
                <AlertTriangle className="w-4 h-4 flex-shrink-0 text-amber-400 mt-0.5" />
              )}
              <div>
                <p className="font-semibold">{artworkStatus.valid ? 'Compliant' : 'Auto-Converted'}</p>
                <p className="text-[10px] opacity-80">{artworkStatus.message}</p>
                {!artworkStatus.valid && (
                  <p className="text-[10px] text-walkman-gold mt-1">
                    Will be re-encoded to Baseline RGB JPEG (subsampling=0) upon saving.
                  </p>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Metadata Fields Form */}
        <div className="md:col-span-2 bg-walkman-card border border-walkman-border rounded-xl p-5 space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-1 block">
                Track Title
              </label>
              <input
                type="text"
                value={formData.title}
                onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                className="w-full bg-walkman-input border border-walkman-border rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-walkman-gold"
              />
            </div>

            <div>
              <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-1 block">
                Artist
              </label>
              <input
                type="text"
                value={formData.artist}
                onChange={(e) => setFormData({ ...formData, artist: e.target.value })}
                className="w-full bg-walkman-input border border-walkman-border rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-walkman-gold"
              />
            </div>

            <div>
              <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-1 block">
                Album
              </label>
              <input
                type="text"
                value={formData.album}
                onChange={(e) => setFormData({ ...formData, album: e.target.value })}
                className="w-full bg-walkman-input border border-walkman-border rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-walkman-gold"
              />
            </div>

            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-1 block">
                  Track #
                </label>
                <input
                  type="text"
                  value={formData.track_number}
                  onChange={(e) => setFormData({ ...formData, track_number: e.target.value })}
                  placeholder="e.g. 1 or 01"
                  className="w-full bg-walkman-input border border-walkman-border rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-walkman-gold"
                />
              </div>
              <div>
                <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-1 block">
                  Year
                </label>
                <input
                  type="text"
                  value={formData.year}
                  onChange={(e) => setFormData({ ...formData, year: e.target.value })}
                  placeholder="e.g. 1973"
                  className="w-full bg-walkman-input border border-walkman-border rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-walkman-gold"
                />
              </div>
            </div>

            <div className="sm:col-span-2">
              <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-1 block">
                Genre
              </label>
              <input
                type="text"
                value={formData.genre}
                onChange={(e) => setFormData({ ...formData, genre: e.target.value })}
                placeholder="e.g. Progressive Rock"
                className="w-full bg-walkman-input border border-walkman-border rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-walkman-gold"
              />
            </div>
          </div>

          {/* Success Banner */}
          {successMsg && (
            <div className="p-3 bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 rounded-lg text-xs flex items-center space-x-2">
              <CheckCircle className="w-4 h-4" />
              <span>{successMsg}</span>
            </div>
          )}

          {/* Save Action */}
          <div className="pt-2 flex items-center justify-end">
            <button
              type="submit"
              disabled={isSaving}
              className="px-5 py-2 rounded-lg bg-gradient-to-r from-amber-500 to-yellow-600 hover:from-amber-400 hover:to-yellow-500 text-black text-xs font-semibold shadow-md flex items-center space-x-2 transition-all active:scale-95 disabled:opacity-50"
            >
              <Save className="w-3.5 h-3.5" />
              <span>{isSaving ? 'Writing Tags...' : 'Save Tags & Re-encode Artwork'}</span>
            </button>
          </div>
        </div>
      </form>
    </div>
  );
};
