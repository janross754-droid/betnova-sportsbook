import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export const supabase = createClient(
  'https://hrtwcfkjohczuykdqxcu.supabase.co',
  'sb_publishable_q0z0e8_CeSVynhz2ZvRg6g_KSh7QLB3',
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true
    }
  }
);
