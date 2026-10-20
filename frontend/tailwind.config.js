/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        walkman: {
          bg: '#0A0A0C',          // Deep obsidian black
          card: '#131316',        // Dark matte panel
          hover: '#1B1B20',       // Hover state
          border: '#27272E',      // Subtle border
          input: '#18181D',       // Input field background
          gold: '#D4AF37',        // Signature Walkman gold
          goldHover: '#C5A059',   // Darker brass gold
          goldLight: '#F3E5AB',   // Highlight gold
          goldGlow: 'rgba(212, 175, 55, 0.15)',
          muted: '#8A8A93',       // Subdued text
          dim: '#55555E',         // Very subdued text
        }
      },
      fontFamily: {
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "Roboto",
          "Helvetica Neue",
          "Arial",
          "sans-serif"
        ],
        mono: [
          "SF Mono",
          "Menlo",
          "Monaco",
          "Courier New",
          "monospace"
        ]
      }
    },
  },
  plugins: [],
};
