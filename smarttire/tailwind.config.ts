// tailwind.config.ts
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{js,ts,jsx,tsx,mdx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          50:  '#fef3dd',
          100: '#fde8bb',
          500: '#d67200',
          600: '#a85800',
          900: '#14130a',
        },
      },
    },
  },
  plugins: [],
}
