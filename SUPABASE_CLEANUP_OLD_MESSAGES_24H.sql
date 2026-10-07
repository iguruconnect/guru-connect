-- GURU CONNECT: Auto-delete private chat messages older than 24 hours
-- Run this SQL in Supabase SQL Editor to set up automatic message cleanup
-- This reduces database storage burden by permanently removing old conversation data

-- ============================================================================
-- FUNCTION: Delete messages older than 24 hours
-- ============================================================================
CREATE OR REPLACE FUNCTION gc_cleanup_old_messages()
RETURNS TABLE(deleted_count INT, last_deleted_at TIMESTAMP) AS $$
DECLARE
  cutoff_time TIMESTAMP;
  rows_deleted INT;
BEGIN
  -- Calculate 24 hours ago
  cutoff_time := NOW() - INTERVAL '24 hours';
  
  -- Delete messages older than 24 hours from gc_learning_request_messages table
  DELETE FROM public.gc_learning_request_messages
  WHERE created_at < cutoff_time;
  
  -- Get count of deleted rows
  GET DIAGNOSTICS rows_deleted = ROW_COUNT;
  
  -- Return results
  RETURN QUERY
  SELECT rows_deleted as deleted_count, cutoff_time as last_deleted_at;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SETUP: Make the function executable by any authenticated user
-- ============================================================================
GRANT EXECUTE ON FUNCTION gc_cleanup_old_messages() TO authenticated;

-- ============================================================================
-- CRON JOB: Schedule the cleanup to run every 6 hours (4 times per day)
-- This ensures messages are deleted regularly without overwhelming the database
-- ============================================================================
-- First, enable the pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule the cleanup function to run every 6 hours
-- The job name is 'gc_cleanup_old_messages_job'
SELECT cron.schedule(
  'gc_cleanup_old_messages_job',     -- Job name
  '0 */6 * * *',                     -- Cron expression: every 6 hours (00:00, 06:00, 12:00, 18:00 UTC)
  'SELECT gc_cleanup_old_messages();'
);

-- ============================================================================
-- ALTERNATIVE CRON SCHEDULES (uncomment if you prefer different timing)
-- ============================================================================

-- Option 1: Every 12 hours (2 times per day) - LESS FREQUENT
-- SELECT cron.schedule(
--   'gc_cleanup_old_messages_job',
--   '0 0,12 * * *',
--   'SELECT gc_cleanup_old_messages();'
-- );

-- Option 2: Every 24 hours (1 time per day) at 3 AM UTC - LEAST FREQUENT
-- SELECT cron.schedule(
--   'gc_cleanup_old_messages_job',
--   '0 3 * * *',
--   'SELECT gc_cleanup_old_messages();'
-- );

-- Option 3: Every 3 hours (8 times per day) - MORE FREQUENT
-- SELECT cron.schedule(
--   'gc_cleanup_old_messages_job',
--   '0 */3 * * *',
--   'SELECT gc_cleanup_old_messages();'
-- );

-- ============================================================================
-- VERIFICATION: Check if the cron job was created successfully
-- ============================================================================
-- Run this query to verify the job exists:
-- SELECT * FROM cron.job WHERE jobname = 'gc_cleanup_old_messages_job';

-- ============================================================================
-- MANUAL EXECUTION: Run the cleanup immediately (optional)
-- ============================================================================
-- If you want to test the function or run it immediately, execute:
-- SELECT * FROM gc_cleanup_old_messages();

-- ============================================================================
-- MONITORING: Check cleanup logs (optional)
-- ============================================================================
-- To see cron job execution history:
-- SELECT * FROM cron.job_run_details WHERE jobname = 'gc_cleanup_old_messages_job' ORDER BY start_time DESC LIMIT 10;

-- ============================================================================
-- DELETE CRON JOB (only if you want to stop the cleanup):
-- ============================================================================
-- SELECT cron.unschedule('gc_cleanup_old_messages_job');

-- ============================================================================
-- NOTES:
-- ============================================================================
-- 1. Messages are PERMANENTLY DELETED from the database after 24 hours
-- 2. The cleanup runs every 6 hours automatically
-- 3. This reduces Supabase storage costs
-- 4. Users cannot see messages older than 24 hours (frontend filters them too)
-- 5. To change the 24-hour window, modify "INTERVAL '24 hours'" in the function
-- 6. To change the cleanup frequency, modify the cron expression (currently '0 */6 * * *')
-- 7. All deleted messages are gone permanently - there's no recovery

