import React, { useState, useEffect } from 'react';
import { Sliders, Save, Cpu, Sparkles, CheckCircle2, FileText, ToggleLeft, ToggleRight } from 'lucide-react';
import { CfwSettings, WalkmanDrive } from '../types';
import { api } from '../api';

interface Props {
  activeDrive: WalkmanDrive | null;
}

export const WalkmanOneDspView: React.FC<Props> = ({ activeDrive }) => {
  const [cfwData, setCfwData] = useState<CfwSettings | null>(null);
  const [loading, setLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [activeMode, setActiveMode] = useState<'visual' | 'raw'>('visual');
  const [rawText, setRawText] = useState('');
  const [soundSignature, setSoundSignature] = useState('WM1Z');
  const [dacGain, setDacGain] = useState('0');
  const [plusV2, setPlusV2] = useState('1');
  const [vinylProcessor, setVinylProcessor] = useState('0');
  const [statusMsg, setStatusMsg] = useState<string | null>(null);

  useEffect(() => {
    if (activeDrive) {
      loadCfw();
    }
  }, [activeDrive]);

  const loadCfw = async () => {
    if (!activeDrive) return;
    setLoading(true);
    try {
      const data = await api.getCfw(activeDrive.mount_point);
      setCfwData(data);
      setRawText(data.raw_text);

      const parsed = data.parsed || {};
      setSoundSignature(parsed['sound_signature'] || 'WM1Z');
      setDacGain(parsed['dac_gain'] || '0');
      setPlusV2(parsed['plus_v2'] || '1');
      setVinylProcessor(parsed['vinyl_processor'] || '0');
    } catch (e: any) {
      console.error('Failed to load CFW settings:', e);
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async () => {
    if (!activeDrive) return;
    setIsSaving(true);
    setStatusMsg(null);

    try {
      if (activeMode === 'raw') {
        await api.saveCfw(activeDrive.mount_point, {}, rawText);
      } else {
        const settings: Record<string, string> = {
          sound_signature: soundSignature,
          dac_gain: dacGain,
          plus_v2: plusV2,
          vinyl_processor: vinylProcessor,
        };
        await api.saveCfw(activeDrive.mount_point, settings);
      }
      setStatusMsg('Walkman One DSP settings written to /CFW/settings.txt');
      await loadCfw();
    } catch (e: any) {
      alert(`Failed to save CFW: ${e.message}`);
    } finally {
      setIsSaving(false);
    }
  };

  const soundSignatures = [
    {
      id: 'WM1Z',
      name: 'Sony NW-WM1Z Signature',
      desc: 'Warm, rich analog timbre with deep bass body and liquid mids.',
      color: 'from-amber-600 to-yellow-600',
    },
    {
      id: 'DMP-Z1',
      name: 'Sony DMP-Z1 Flagship',
      desc: 'Expansive holographic soundstage, ultra-high resolution and spatial separation.',
      color: 'from-yellow-700 to-amber-500',
    },
    {
      id: 'ZX300',
      name: 'Sony NW-ZX300',
      desc: 'Punchy transients, balanced low-end impact, crisp modern highs.',
      color: 'from-zinc-600 to-zinc-400',
    },
    {
      id: 'Neutral',
      name: 'Reference Neutral',
      desc: 'Uncolored monitoring frequency response for strict audiophile transparency.',
      color: 'from-emerald-700 to-teal-600',
    },
  ];

  if (!activeDrive) {
    return (
      <div className="p-12 text-center text-zinc-500 max-w-xl mx-auto my-12 border border-dashed border-zinc-800 rounded-2xl bg-zinc-900/20">
        <Sliders className="w-12 h-12 text-zinc-700 mx-auto mb-3" />
        <h3 className="text-base font-medium text-white mb-1">No Drive Selected</h3>
        <p className="text-xs text-zinc-500">
          Connect your Walkman or select a drive to tweak Walkman One Custom Firmware parameters.
        </p>
      </div>
    );
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div>
          <div className="flex items-center space-x-2">
            <h2 className="text-base font-semibold text-white">Walkman One CFW DSP Tweaker</h2>
            <span className="px-2 py-0.5 rounded text-[10px] font-mono font-medium bg-amber-500/10 text-walkman-gold border border-amber-500/20">
              MrWalkman CFW
            </span>
          </div>
          <p className="text-xs text-zinc-400">
            Real-time hardware tuning stored at <span className="font-mono text-zinc-300">/CFW/settings.txt</span> on {activeDrive.name}
          </p>
        </div>

        {/* Mode Switch & Save */}
        <div className="flex items-center space-x-3">
          <div className="flex rounded-lg bg-zinc-900 border border-walkman-border p-0.5">
            <button
              onClick={() => setActiveMode('visual')}
              className={`px-3 py-1 rounded-md text-xs font-medium transition-all ${
                activeMode === 'visual'
                  ? 'bg-walkman-hover text-walkman-gold shadow-sm font-semibold'
                  : 'text-zinc-400 hover:text-white'
              }`}
            >
              Sound Models
            </button>
            <button
              onClick={() => setActiveMode('raw')}
              className={`px-3 py-1 rounded-md text-xs font-medium transition-all ${
                activeMode === 'raw'
                  ? 'bg-walkman-hover text-walkman-gold shadow-sm font-semibold'
                  : 'text-zinc-400 hover:text-white'
              }`}
            >
              Raw Editor
            </button>
          </div>

          <button
            onClick={handleSave}
            disabled={isSaving}
            className="px-4 py-1.5 rounded-lg bg-gradient-to-r from-amber-500 to-yellow-600 hover:from-amber-400 hover:to-yellow-500 text-black text-xs font-semibold shadow-md flex items-center space-x-2 transition-all active:scale-95 disabled:opacity-50"
          >
            <Save className="w-3.5 h-3.5" />
            <span>{isSaving ? 'Writing...' : 'Apply to Walkman'}</span>
          </button>
        </div>
      </div>

      {statusMsg && (
        <div className="p-3 bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 rounded-lg text-xs flex items-center space-x-2">
          <CheckCircle2 className="w-4 h-4" />
          <span>{statusMsg}</span>
        </div>
      )}

      {activeMode === 'visual' ? (
        <div className="space-y-6">
          {/* Sound Signatures Grid */}
          <div>
            <label className="text-[11px] uppercase font-semibold text-zinc-400 tracking-wider mb-3 block">
              Flagship Tuning Profile
            </label>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {soundSignatures.map((sig) => {
                const isSelected = soundSignature === sig.id;
                return (
                  <div
                    key={sig.id}
                    onClick={() => setSoundSignature(sig.id)}
                    className={`p-4 rounded-xl border cursor-pointer transition-all ${
                      isSelected
                        ? 'bg-walkman-input border-walkman-gold shadow-lg shadow-amber-950/20'
                        : 'bg-walkman-card border-walkman-border hover:border-zinc-700'
                    }`}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center space-x-2">
                        <div
                          className={`w-3 h-3 rounded-full bg-gradient-to-br ${sig.color}`}
                        />
                        <span className="font-semibold text-sm text-white">{sig.name}</span>
                      </div>
                      {isSelected && (
                        <span className="px-2 py-0.5 rounded text-[10px] bg-amber-500/20 text-walkman-gold font-mono font-medium">
                          Active
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-zinc-400">{sig.desc}</p>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Hardware DAC & DSP Toggles */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {/* DAC Gain */}
            <div className="p-4 bg-walkman-card border border-walkman-border rounded-xl space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold text-white">Hardware DAC Gain</span>
                <button
                  type="button"
                  onClick={() => setDacGain(dacGain === '1' ? '0' : '1')}
                  className="text-walkman-gold"
                >
                  {dacGain === '1' ? (
                    <ToggleRight className="w-7 h-7 text-walkman-gold" />
                  ) : (
                    <ToggleLeft className="w-7 h-7 text-zinc-600" />
                  )}
                </button>
              </div>
              <p className="text-[11px] text-zinc-400">
                {dacGain === '1'
                  ? 'High Gain: Recommended for planar magnetic / high-impedance headphones.'
                  : 'Standard Gain: Ultra-low noise floor for high-sensitivity IEMs.'}
              </p>
            </div>

            {/* Plus v2 DSP */}
            <div className="p-4 bg-walkman-card border border-walkman-border rounded-xl space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold text-white">Plus v2 DSP Enhancer</span>
                <button
                  type="button"
                  onClick={() => setPlusV2(plusV2 === '1' ? '0' : '1')}
                  className="text-walkman-gold"
                >
                  {plusV2 === '1' ? (
                    <ToggleRight className="w-7 h-7 text-walkman-gold" />
                  ) : (
                    <ToggleLeft className="w-7 h-7 text-zinc-600" />
                  )}
                </button>
              </div>
              <p className="text-[11px] text-zinc-400">
                Enables MrWalkman's revised digital sound processing filter matrix.
              </p>
            </div>

            {/* Vinyl Processor */}
            <div className="p-4 bg-walkman-card border border-walkman-border rounded-xl space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold text-white">Vinyl Processor</span>
                <button
                  type="button"
                  onClick={() => setVinylProcessor(vinylProcessor === '1' ? '0' : '1')}
                  className="text-walkman-gold"
                >
                  {vinylProcessor === '1' ? (
                    <ToggleRight className="w-7 h-7 text-walkman-gold" />
                  ) : (
                    <ToggleLeft className="w-7 h-7 text-zinc-600" />
                  )}
                </button>
              </div>
              <p className="text-[11px] text-zinc-400">
                Simulates tonearm resonance and turntable acoustic surface acoustics.
              </p>
            </div>
          </div>
        </div>
      ) : (
        /* Raw Editor Mode */
        <div className="bg-walkman-card border border-walkman-border rounded-xl p-5 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-white flex items-center space-x-1.5">
              <FileText className="w-4 h-4 text-walkman-gold" />
              <span>Direct /CFW/settings.txt Editor</span>
            </span>
            <span className="text-[10px] text-zinc-500">Key = Value directives</span>
          </div>
          <textarea
            rows={10}
            value={rawText}
            onChange={(e) => setRawText(e.target.value)}
            className="w-full bg-walkman-input border border-walkman-border rounded-lg p-3 text-xs font-mono text-zinc-200 focus:outline-none focus:border-walkman-gold"
          />
        </div>
      )}
    </div>
  );
};
