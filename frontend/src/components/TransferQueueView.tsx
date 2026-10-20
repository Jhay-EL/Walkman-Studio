import React, { useState } from 'react';
import { UploadCloud, Play, CheckCircle2, AlertCircle, Trash2, ArrowRight } from 'lucide-react';
import { WalkmanDrive, TransferQueueItem } from '../types';
import { api } from '../api';

interface Props {
  drives: WalkmanDrive[];
  activeDrive: WalkmanDrive | null;
  onTransferComplete: () => void;
}

export const TransferQueueView: React.FC<Props> = ({
  drives,
  activeDrive,
  onTransferComplete,
}) => {
  const [targetDriveId, setTargetDriveId] = useState<string>(activeDrive?.id || drives[0]?.id || '');
  const [preset, setPreset] = useState<string>('copy');
  const [filePathInput, setFilePathInput] = useState<string>('');
  const [queue, setQueue] = useState<TransferQueueItem[]>([]);
  const [isProcessing, setIsProcessing] = useState<boolean>(false);
  const [currentProgress, setCurrentProgress] = useState<number>(0);

  const selectedTarget = drives.find((d) => d.id === targetDriveId) || activeDrive;

  const handleAddPaths = () => {
    if (!filePathInput.trim()) return;
    const paths = filePathInput
      .split('\n')
      .map((p) => p.trim())
      .filter((p) => p.length > 0);

    const newItems: TransferQueueItem[] = paths.map((p) => ({
      id: Math.random().toString(36).substring(2, 9),
      path: p,
      filename: p.split('/').pop() || p,
      status: 'pending',
    }));

    setQueue((prev) => [...prev, ...newItems]);
    setFilePathInput('');
  };

  const handleRemove = (id: string) => {
    setQueue((prev) => prev.filter((item) => item.id !== id));
  };

  const handleClear = () => {
    setQueue([]);
  };

  const startBatchTransfer = async () => {
    if (!selectedTarget) {
      alert('Please select a target Walkman drive.');
      return;
    }
    if (queue.length === 0) return;

    setIsProcessing(true);
    setCurrentProgress(0);

    const filePaths = queue.map((q) => q.path);

    try {
      // Mark all as converting
      setQueue((prev) => prev.map((q) => ({ ...q, status: 'converting' })));

      const res = await api.transferFiles({
        source_files: filePaths,
        target_mount: selectedTarget.mount_point,
        preset: preset,
      });

      // Update queue with results
      const resultsMap = new Map();
      res.results.forEach((r: any) => resultsMap.set(r.source, r));

      setQueue((prev) =>
        prev.map((item) => {
          const r = resultsMap.get(item.path);
          if (r && r.success) {
            return { ...item, status: 'success', targetPath: r.target };
          } else {
            return { ...item, status: 'error', error: r?.error || 'Transfer failed' };
          }
        })
      );

      setCurrentProgress(100);
      onTransferComplete();
    } catch (e: any) {
      alert(`Transfer error: ${e?.response?.data?.detail || e.message}`);
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <div className="p-6 space-y-6 max-w-7xl mx-auto">
      {/* Top Banner & Drive Picker */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* Destination Drive Selection */}
        <div className="p-4 bg-walkman-card border border-walkman-border rounded-xl">
          <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-2 block">
            Destination Drive
          </label>
          <select
            value={targetDriveId}
            onChange={(e) => setTargetDriveId(e.target.value)}
            className="w-full bg-walkman-input border border-walkman-border rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-walkman-gold"
          >
            {drives.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name} ({d.type.toUpperCase()})
              </option>
            ))}
          </select>
          <p className="text-[10px] text-zinc-500 mt-2">
            Target folder: <span className="font-mono text-zinc-400">/MUSIC/Artist/Album/</span>
          </p>
        </div>

        {/* Transcode Preset */}
        <div className="p-4 bg-walkman-card border border-walkman-border rounded-xl">
          <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-2 block">
            Conversion Preset
          </label>
          <select
            value={preset}
            onChange={(e) => setPreset(e.target.value)}
            className="w-full bg-walkman-input border border-walkman-border rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-walkman-gold"
          >
            <option value="copy">Direct Copy (Pass-through if FLAC/MP3)</option>
            <option value="flac_16">Transcode to FLAC 16-bit (Lossless CD Quality)</option>
            <option value="flac_24">Transcode to FLAC 24-bit (Hi-Res Audio)</option>
            <option value="mp3_320">Transcode to MP3 320 kbps (Strict ID3v2.3)</option>
          </select>
          <p className="text-[10px] text-zinc-500 mt-2">
            Hardware acceleration via <span className="font-mono text-zinc-400">ffmpeg Apple Silicon</span>
          </p>
        </div>

        {/* Start Action Box */}
        <div className="p-4 bg-walkman-card border border-walkman-border rounded-xl flex flex-col justify-between">
          <div>
            <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-1 block">
              Batch Status
            </label>
            <p className="text-xs text-zinc-300">
              <span className="font-semibold text-walkman-gold">{queue.length}</span> items in queue
            </p>
          </div>
          <button
            onClick={startBatchTransfer}
            disabled={queue.length === 0 || isProcessing}
            className="w-full mt-3 py-2 px-4 rounded-lg bg-gradient-to-r from-amber-500 to-yellow-600 hover:from-amber-400 hover:to-yellow-500 text-black text-xs font-semibold shadow-md flex items-center justify-center space-x-2 transition-all active:scale-95 disabled:opacity-40"
          >
            <Play className={`w-3.5 h-3.5 ${isProcessing ? 'animate-spin' : ''}`} />
            <span>{isProcessing ? 'Processing Transcodes...' : 'Start Transfer & Convert'}</span>
          </button>
        </div>
      </div>

      {/* Input / Drop Zone */}
      <div className="p-5 bg-walkman-card border border-walkman-border rounded-xl space-y-3">
        <div className="flex items-center justify-between">
          <label className="text-xs font-medium text-white flex items-center space-x-2">
            <UploadCloud className="w-4 h-4 text-walkman-gold" />
            <span>Add Audio Files by Local Path (or drag & drop text paths)</span>
          </label>
          <span className="text-[11px] text-zinc-500">Supports FLAC, MP3, WAV, ALAC, M4A, AIFF</span>
        </div>
        <textarea
          rows={3}
          value={filePathInput}
          onChange={(e) => setFilePathInput(e.target.value)}
          placeholder="Paste absolute file paths here (one per line), e.g.&#10;/Users/username/Music/Album/01 - Song.flac"
          className="w-full bg-walkman-input border border-walkman-border rounded-lg p-3 text-xs font-mono text-zinc-200 placeholder-zinc-600 focus:outline-none focus:border-walkman-gold transition-colors"
        />
        <div className="flex items-center justify-between">
          <button
            onClick={handleAddPaths}
            disabled={!filePathInput.trim()}
            className="px-4 py-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-white text-xs font-medium transition-all disabled:opacity-40"
          >
            Add to Transfer Queue
          </button>
          {queue.length > 0 && (
            <button
              onClick={handleClear}
              className="text-xs text-zinc-500 hover:text-red-400 flex items-center space-x-1"
            >
              <Trash2 className="w-3.5 h-3.5" />
              <span>Clear Queue</span>
            </button>
          )}
        </div>
      </div>

      {/* Transfer Queue Table */}
      {queue.length > 0 && (
        <div className="bg-walkman-card border border-walkman-border rounded-xl overflow-hidden shadow-sm">
          <div className="p-3 bg-zinc-900/60 border-b border-walkman-border flex items-center justify-between text-xs font-medium text-zinc-400">
            <span>Queue Items</span>
            <span className="text-[11px] font-mono">
              {queue.filter((q) => q.status === 'success').length} / {queue.length} completed
            </span>
          </div>
          <table className="w-full text-left text-xs text-zinc-300">
            <tbody className="divide-y divide-zinc-800/50">
              {queue.map((item) => (
                <tr key={item.id} className="hover:bg-walkman-hover/40 transition-colors">
                  <td className="py-2.5 px-4 font-medium text-white truncate max-w-sm">
                    {item.filename}
                    <div className="text-[10px] text-zinc-500 font-mono truncate">{item.path}</div>
                  </td>
                  <td className="py-2.5 px-4 w-32 text-center">
                    {item.status === 'pending' && (
                      <span className="px-2 py-0.5 rounded text-[10px] bg-zinc-800 text-zinc-400">
                        Pending
                      </span>
                    )}
                    {item.status === 'converting' && (
                      <span className="px-2 py-0.5 rounded text-[10px] bg-amber-500/10 text-walkman-gold border border-amber-500/30 animate-pulse">
                        Converting...
                      </span>
                    )}
                    {item.status === 'success' && (
                      <span className="px-2 py-0.5 rounded text-[10px] bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center justify-center space-x-1">
                        <CheckCircle2 className="w-3 h-3" />
                        <span>Transferred</span>
                      </span>
                    )}
                    {item.status === 'error' && (
                      <span
                        title={item.error}
                        className="px-2 py-0.5 rounded text-[10px] bg-red-500/10 text-red-400 border border-red-500/20 flex items-center justify-center space-x-1"
                      >
                        <AlertCircle className="w-3 h-3" />
                        <span>Failed</span>
                      </span>
                    )}
                  </td>
                  <td className="py-2.5 px-4 w-12 text-center">
                    <button
                      onClick={() => handleRemove(item.id)}
                      disabled={isProcessing}
                      className="p-1 text-zinc-600 hover:text-zinc-400"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};
