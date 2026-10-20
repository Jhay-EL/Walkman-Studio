import React, { useState } from 'react';
import { X, Trash2, CheckCircle2, AlertCircle, ShieldCheck, HardDrive } from 'lucide-react';
import { WalkmanDrive } from '../types';
import { api } from '../api';

interface Props {
  isOpen: boolean;
  onClose: () => void;
  activeDrive: WalkmanDrive | null;
  onEjected: () => void;
}

export const CleanEjectModal: React.FC<Props> = ({
  isOpen,
  onClose,
  activeDrive,
  onEjected,
}) => {
  const [cleaning, setCleaning] = useState(false);
  const [cleanLog, setCleanLog] = useState<{
    dotCleanRun?: boolean;
    deletedFiles?: string[];
    unmountMsg?: string;
    success?: boolean;
    error?: string;
  } | null>(null);

  if (!isOpen || !activeDrive) return null;

  const handleExecute = async () => {
    setCleaning(true);
    setCleanLog(null);
    try {
      const res = await api.cleanAndEject(activeDrive.mount_point);
      setCleanLog({
        dotCleanRun: res.clean_results?.dot_clean_run,
        deletedFiles: res.clean_results?.deleted_files,
        unmountMsg: res.unmount_results?.message || 'Drive safely unmounted',
        success: res.unmount_results?.success ?? true,
      });
      onEjected();
    } catch (e: any) {
      setCleanLog({
        success: false,
        error: e?.response?.data?.detail || e.message,
      });
    } finally {
      setCleaning(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-sm p-4">
      <div className="w-full max-w-md bg-walkman-card border border-walkman-border rounded-2xl shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-150">
        {/* Header */}
        <div className="p-4 border-b border-walkman-border flex items-center justify-between">
          <div className="flex items-center space-x-2 text-walkman-gold">
            <Trash2 className="w-4 h-4" />
            <h3 className="text-sm font-semibold text-white">Clean Junk & Safe Eject</h3>
          </div>
          <button
            onClick={onClose}
            disabled={cleaning}
            className="p-1 rounded text-zinc-500 hover:text-white"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Content */}
        <div className="p-5 space-y-4 text-xs">
          <div className="p-3 rounded-lg bg-zinc-900 border border-zinc-800 flex items-center space-x-3">
            <HardDrive className="w-5 h-5 text-walkman-gold flex-shrink-0" />
            <div className="truncate">
              <p className="font-semibold text-white">{activeDrive.name}</p>
              <p className="text-[10px] text-zinc-500 font-mono truncate">
                {activeDrive.mount_point}
              </p>
            </div>
          </div>

          {!cleanLog ? (
            <div className="space-y-3 text-zinc-400">
              <p>
                macOS automatically places hidden spotlight indexes, resource forks, and junk files on FAT32/exFAT drives.
              </p>
              <div className="p-3 rounded-lg bg-walkman-bg border border-zinc-800 space-y-1.5 text-[11px]">
                <p className="font-medium text-white flex items-center space-x-1.5">
                  <ShieldCheck className="w-3.5 h-3.5 text-walkman-gold" />
                  <span>Sanitization Sequence:</span>
                </p>
                <ul className="list-disc pl-5 space-y-1 text-zinc-400">
                  <li>Run native <code className="text-amber-300 font-mono">dot_clean -m</code></li>
                  <li>Purge <code className="text-amber-300 font-mono">.DS_Store</code>, <code className="text-amber-300 font-mono">._*</code> files</li>
                  <li>Remove <code className="text-amber-300 font-mono">.Spotlight-V100</code>, <code className="text-amber-300 font-mono">.Trashes</code></li>
                  <li>Execute safe macOS unmount via <code className="text-amber-300 font-mono">diskutil unmount</code></li>
                </ul>
              </div>
            </div>
          ) : (
            <div className="space-y-3">
              {cleanLog.success ? (
                <div className="p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-center space-y-1.5">
                  <CheckCircle2 className="w-8 h-8 mx-auto text-emerald-400" />
                  <h4 className="font-semibold text-sm">Safe to Disconnect Walkman</h4>
                  <p className="text-[11px] opacity-80">
                    All macOS ghost files were purged and {activeDrive.name} has been unmounted.
                  </p>
                  {cleanLog.deletedFiles && cleanLog.deletedFiles.length > 0 && (
                    <p className="text-[10px] text-zinc-400 font-mono mt-1">
                      Removed {cleanLog.deletedFiles.length} junk files
                    </p>
                  )}
                </div>
              ) : (
                <div className="p-4 rounded-xl bg-red-500/10 border border-red-500/30 text-red-400 text-center space-y-1.5">
                  <AlertCircle className="w-8 h-8 mx-auto text-red-400" />
                  <h4 className="font-semibold text-sm">Eject Failed</h4>
                  <p className="text-[11px] opacity-80">{cleanLog.error || cleanLog.unmountMsg}</p>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer Actions */}
        <div className="p-4 bg-zinc-900/60 border-t border-walkman-border flex items-center justify-end space-x-2">
          {!cleanLog ? (
            <>
              <button
                onClick={onClose}
                disabled={cleaning}
                className="px-3 py-1.5 rounded-lg text-xs text-zinc-400 hover:text-white"
              >
                Cancel
              </button>
              <button
                onClick={handleExecute}
                disabled={cleaning}
                className="px-4 py-1.5 rounded-lg bg-gradient-to-r from-amber-500 to-yellow-600 hover:from-amber-400 hover:to-yellow-500 text-black text-xs font-semibold shadow-md flex items-center space-x-1.5 transition-all active:scale-95 disabled:opacity-50"
              >
                <Trash2 className="w-3.5 h-3.5" />
                <span>{cleaning ? 'Purging & Ejecting...' : 'Clean & Eject Now'}</span>
              </button>
            </>
          ) : (
            <button
              onClick={onClose}
              className="px-4 py-1.5 rounded-lg bg-zinc-800 hover:bg-zinc-700 text-white text-xs font-medium"
            >
              Close
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
