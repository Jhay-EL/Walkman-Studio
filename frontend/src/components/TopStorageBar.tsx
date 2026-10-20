import React from 'react';
import { HardDrive, Disc, ShieldCheck, Trash2, RefreshCw } from 'lucide-react';
import { WalkmanDrive } from '../types';

interface Props {
  drives: WalkmanDrive[];
  activeDrive: WalkmanDrive | null;
  onSelectDrive: (drive: WalkmanDrive) => void;
  onRefresh: () => void;
  onOpenEject: () => void;
  loading: boolean;
}

export const TopStorageBar: React.FC<Props> = ({
  drives,
  activeDrive,
  onSelectDrive,
  onRefresh,
  onOpenEject,
  loading,
}) => {
  const formatBytes = (bytes: number): string => {
    if (!bytes || bytes === 0) return '0 GB';
    const gb = bytes / (1024 * 1024 * 1024);
    if (gb < 1) {
      const mb = bytes / (1024 * 1024);
      return `${mb.toFixed(0)} MB`;
    }
    return `${gb.toFixed(1)} GB`;
  };

  const internalDrive = drives.find((d) => d.type === 'internal');
  const microsdDrive = drives.find((d) => d.type === 'microsd');

  return (
    <header className="bg-walkman-card border-b border-walkman-border px-6 py-3 flex items-center justify-between sticky top-0 z-30 shadow-md">
      {/* Branding & Model */}
      <div className="flex items-center space-x-3">
        <div className="w-9 h-9 rounded-lg bg-gradient-to-br from-amber-500 to-yellow-600 flex items-center justify-center shadow-lg shadow-amber-900/20 border border-amber-400/40">
          <span className="font-bold text-black text-sm tracking-tighter">W.</span>
        </div>
        <div>
          <div className="flex items-center space-x-2">
            <h1 className="text-sm font-semibold tracking-wide text-white">WALKMAN STUDIO</h1>
            <span className="px-1.5 py-0.5 rounded text-[10px] font-mono font-medium bg-amber-500/10 text-walkman-gold border border-amber-500/20">
              NW-A55L
            </span>
          </div>
          <p className="text-[11px] text-walkman-muted flex items-center space-x-1.5">
            <span>Apple Silicon Native</span>
            <span className="text-zinc-600">•</span>
            <span className="text-amber-400/90 font-medium">Signature Edition</span>
          </p>
        </div>
      </div>

      {/* Dual Storage Drives Gauge */}
      <div className="flex items-center space-x-4">
        {/* Internal Drive */}
        {internalDrive ? (
          <div
            onClick={() => onSelectDrive(internalDrive)}
            className={`cursor-pointer px-4 py-2 rounded-lg border transition-all ${
              activeDrive?.id === internalDrive.id
                ? 'bg-walkman-input border-walkman-gold text-white shadow-sm'
                : 'bg-zinc-900/40 border-walkman-border text-zinc-400 hover:border-zinc-600'
            }`}
          >
            <div className="flex items-center justify-between space-x-3 mb-1.5 text-xs">
              <div className="flex items-center space-x-1.5">
                <HardDrive className={`w-3.5 h-3.5 ${activeDrive?.id === internalDrive.id ? 'text-walkman-gold' : 'text-zinc-500'}`} />
                <span className="font-medium text-white">{internalDrive.name}</span>
              </div>
              <div className="text-[11px] font-mono text-zinc-300 flex items-center space-x-1">
                <span className="text-white font-semibold">{formatBytes(internalDrive.free_bytes)}</span>
                <span className="text-zinc-500">/ {formatBytes(internalDrive.total_bytes)} free</span>
              </div>
            </div>
            {/* Progress Gauge */}
            <div className="w-48 h-1.5 bg-zinc-800 rounded-full overflow-hidden">
              <div
                className="h-full bg-gradient-to-r from-amber-600 to-walkman-gold transition-all duration-500"
                style={{ width: `${Math.min(100, internalDrive.percent_used)}%` }}
              />
            </div>
          </div>
        ) : (
          <div className="px-3 py-1.5 rounded border border-dashed border-zinc-800 text-xs text-zinc-500">
            Internal Drive: Disconnected
          </div>
        )}

        {/* MicroSD Drive */}
        {microsdDrive ? (
          <div
            onClick={() => onSelectDrive(microsdDrive)}
            className={`cursor-pointer px-4 py-2 rounded-lg border transition-all ${
              activeDrive?.id === microsdDrive.id
                ? 'bg-walkman-input border-walkman-gold text-white shadow-sm'
                : 'bg-zinc-900/40 border-walkman-border text-zinc-400 hover:border-zinc-600'
            }`}
          >
            <div className="flex items-center justify-between space-x-3 mb-1.5 text-xs">
              <div className="flex items-center space-x-1.5">
                <Disc className={`w-3.5 h-3.5 ${activeDrive?.id === microsdDrive.id ? 'text-walkman-gold' : 'text-zinc-500'}`} />
                <span className="font-medium text-white">{microsdDrive.name}</span>
              </div>
              <div className="text-[11px] font-mono text-zinc-300 flex items-center space-x-1">
                <span className="text-white font-semibold">{formatBytes(microsdDrive.free_bytes)}</span>
                <span className="text-zinc-500">/ {formatBytes(microsdDrive.total_bytes)} free</span>
              </div>
            </div>
            {/* Progress Gauge */}
            <div className="w-48 h-1.5 bg-zinc-800 rounded-full overflow-hidden">
              <div
                className="h-full bg-gradient-to-r from-yellow-700 to-amber-500 transition-all duration-500"
                style={{ width: `${Math.min(100, microsdDrive.percent_used)}%` }}
              />
            </div>
          </div>
        ) : (
          <div className="px-3 py-1.5 rounded border border-dashed border-zinc-800 text-xs text-zinc-500">
            MicroSD: Empty
          </div>
        )}

        {/* Refresh Drives */}
        <button
          onClick={onRefresh}
          disabled={loading}
          title="Rescan Walkman Drives"
          className="p-2 rounded-lg bg-walkman-input border border-walkman-border hover:border-walkman-gold/50 text-zinc-400 hover:text-walkman-gold transition-all"
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-walkman-gold' : ''}`} />
        </button>
      </div>

      {/* 1-Click Clean Junk & Safe Eject */}
      <div className="flex items-center space-x-3">
        <button
          onClick={onOpenEject}
          disabled={!activeDrive}
          className="flex items-center space-x-2 px-3.5 py-1.5 rounded-lg bg-zinc-900 hover:bg-zinc-800 border border-amber-500/40 text-walkman-gold hover:text-walkman-goldLight text-xs font-medium transition-all shadow-sm active:scale-95 disabled:opacity-50"
        >
          <Trash2 className="w-3.5 h-3.5 text-walkman-gold" />
          <span>Clean Junk & Safe Eject</span>
        </button>
      </div>
    </header>
  );
};
