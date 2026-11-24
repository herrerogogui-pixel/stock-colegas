// =====================================================
//  CONFIGURACIÓN - completá estos 2 datos de Supabase
//  (Supabase > Project Settings > API)
// =====================================================
window.CONFIG = {
  url: 'https://rffqxbwrdjkgmmdqmmtj.supabase.co',   // "Project URL"
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJmZnF4YndyZGprZ21tZHFtbXRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU1NDk4NTEsImV4cCI6MjExMTEyNTg1MX0.IzVF_A1_WPTYDVJBr_bdvoIjJAWEZGA784uMwuWrqJ8',        // "anon public" key (es pública, no es secreta)

  // No hace falta tocar esto:
  domain: 'stockcolegas.app',   // los usuarios se guardan como usuario@stockcolegas.app
  staleDays: 15                 // a partir de cuántos días un precio se marca como "viejo"
};
