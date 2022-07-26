--
-- Copyright 2022 The Android Open Source Project
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     https://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- Create the base table (`android_jank_cuj`) containing all completed CUJs
-- found in the trace.
SELECT RUN_METRIC('android/jank/cujs.sql');

-- Create tables to store each CUJs main, render, HWC release,
-- and GPU completion threads.
SELECT RUN_METRIC('android/jank/relevant_threads.sql');

-- Create tables to store the main slices on each of the relevant threads
-- * `Choreographer#doFrame` on the main thread
-- * `DrawFrames on the render` thread
-- * `waiting for HWC release` on the HWC release thread
-- * `Waiting for GPU completion` on the GPU completion thread
-- Also extracts vsync ids and GPU completion fence ids that allow us to match
-- slices to concrete vsync IDs.
-- We only store the slices that were produced for the vsyncs within the
-- CUJ markers.
SELECT RUN_METRIC('android/jank/relevant_slices.sql');

-- Computes the boundaries of specific frames and overall CUJ boundaries
-- on specific important threads since each thread will work on a frame at a
-- slightly different time.
-- We also compute the corrected CUJ ts boundaries. This is necessary because
-- the instrumentation logs begin/end CUJ markers *during* the first frame and
-- typically *right at the start* of the last CUJ frame. The ts boundaries in
-- `android_jank_cuj` table are based on these markers so do not actually
-- contain the whole CUJ, but instead overlap with all Choreographer#doFrame
-- slices that belong to a CUJ.
SELECT RUN_METRIC('android/jank/cujs_boundaries.sql');

-- With relevant slices and corrected boundaries we can now estimate the ts
-- boundaries of each frame within the CUJ.
-- We also match with the data from the actual timeline to check which frames
-- missed the deadline and whether this was due to the app or SF.
SELECT RUN_METRIC('android/jank/frames.sql');

-- Creates tables with slices from various relevant threads that are within
-- the CUJ boundaries. Used as data sources for further processing and
-- jank cause analysis of traces.
SELECT RUN_METRIC('android/jank/slices.sql');

-- Creates tables and functions to be used for manual investigations and
-- jank cause analysis of traces.
SELECT RUN_METRIC('android/jank/internal/query_base.sql');
SELECT RUN_METRIC('android/jank/query_functions.sql');

-- Creates a table that matches CUJ counters with the correct CUJs.
-- After the CUJ ends FrameTracker emits counters with the number of total
-- frames, missed frames, longest frame duration, etc.
-- The same numbers are also reported by FrameTracker to statsd.
SELECT RUN_METRIC('android/jank/internal/counters.sql');

-- Creates derived events to visualize a few of the the created tables.
-- Used only for debugging so by default not used and not displayed in the UI.
-- See https://perfetto.dev/docs/contributing/common-tasks#adding-new-derived-events
-- for instructions on how to add these events to the UI.
SELECT RUN_METRIC('android/jank/internal/derived_events.sql');


DROP VIEW IF EXISTS android_jank_cuj_output;
CREATE VIEW android_jank_cuj_output AS
SELECT
  AndroidJankCujMetric(
    'cuj', (
      SELECT RepeatedField(
        AndroidJankCujMetric_Cuj(
          'id', cuj_id,
          'name', cuj_name,
          'process', process_metadata,
          'ts', boundary.ts,
          'dur', boundary.dur,
          'counter_metrics', (
            SELECT AndroidJankCujMetric_Metrics(
              'total_frames', total_frames,
              'missed_frames', missed_frames,
              'missed_app_frames', missed_app_frames,
              'missed_sf_frames', missed_sf_frames,
              'missed_frames_max_successive', missed_frames_max_successive,
              'frame_dur_max', frame_dur_max)
            FROM android_jank_cuj_counter_metrics cm
            WHERE cm.cuj_id = cuj.cuj_id),
          'trace_metrics', (
            SELECT AndroidJankCujMetric_Metrics(
              'total_frames', COUNT(*),
              'missed_frames', SUM(app_missed OR sf_missed),
              'missed_app_frames', SUM(app_missed),
              'missed_sf_frames', SUM(sf_missed),
              'frame_dur_max', MAX(f.dur),
              'frame_dur_avg', CAST(AVG(f.dur) AS INTEGER),
              'frame_dur_p50', CAST(PERCENTILE(f.dur, 50) AS INTEGER),
              'frame_dur_p90', CAST(PERCENTILE(f.dur, 90) AS INTEGER),
              'frame_dur_p95', CAST(PERCENTILE(f.dur, 95) AS INTEGER),
              'frame_dur_p99', CAST(PERCENTILE(f.dur, 99) AS INTEGER))
            FROM android_jank_cuj_frame f
            WHERE f.cuj_id = cuj.cuj_id),
          'timeline_metrics', (
            SELECT AndroidJankCujMetric_Metrics(
              'total_frames', COUNT(*),
              'missed_frames', SUM(app_missed OR sf_missed),
              'missed_app_frames', SUM(app_missed),
              'missed_sf_frames', SUM(sf_missed),
              'frame_dur_max', MAX(f.dur),
              'frame_dur_avg', CAST(AVG(f.dur) AS INTEGER),
              'frame_dur_p50', CAST(PERCENTILE(f.dur, 50) AS INTEGER),
              'frame_dur_p90', CAST(PERCENTILE(f.dur, 90) AS INTEGER),
              'frame_dur_p95', CAST(PERCENTILE(f.dur, 95) AS INTEGER),
              'frame_dur_p99', CAST(PERCENTILE(f.dur, 99) AS INTEGER))
            FROM android_jank_cuj_frame_timeline f
            WHERE f.cuj_id = cuj.cuj_id),
          'frame', (
            SELECT RepeatedField(
              AndroidJankCujMetric_Frame(
                'frame_number', f.frame_number,
                'vsync', f.vsync,
                'ts', f.ts,
                'dur', f.dur,
                'dur_expected', f.dur_expected,
                'app_missed', f.app_missed,
                'sf_missed', f.sf_missed))
          FROM android_jank_cuj_frame f
          WHERE f.cuj_id = cuj.cuj_id
          ORDER BY frame_number ASC)
          ))
      FROM android_jank_cuj cuj
      JOIN android_jank_cuj_boundary boundary USING (cuj_id)
      ORDER BY cuj.cuj_id ASC));