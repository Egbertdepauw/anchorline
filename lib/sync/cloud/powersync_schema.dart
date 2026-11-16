/// PowerSync schema for the sync-eligible tables.
///
/// Mirrors the Postgres tables in `supabase/migrations/0001_initial_schema.sql`
/// and `supabase/migrations/0003_dives_and_samples.sql`. PowerSync auto-adds
/// `id text not null primary key` per table, so the schemas below list every
/// other column. JSONB columns become `Column.text` (encode/decode in Dart).
/// Timestamps are millis-since-epoch in `Column.integer`.
///
/// Composite-PK Drift tables synthesize their `id` client-side:
///   - `pressure_mappings.id` = `"<dive_computer_id>:<channel_index>"`
///   - `dive_cylinders.id`    = `"<dive_id>:<gas_mix_index>"`
/// The cloud Postgres schema enforces uniqueness on the underlying composite.
///
/// `dive_samples` is 1:1 with `dives`: its `id` column is both the PK
/// and the FK to `dives.id`, so a samples row carries the same id as
/// its parent dive. PowerSync's sync rules require an `id` column on
/// every result row, hence the alignment.
///
/// Sample blobs are gzipped Float32 columnar binary; PowerSync only
/// supports text/integer/real, so they live as base64-encoded text and
/// get decoded back to bytes at the seam.
library;

import 'package:powersync/powersync.dart';

const appSchema = Schema([
  Table('dive_annotations', [
    Column.text('owner_id'),
    Column.text('dive_id'),
    Column.text('site_name'),
    Column.integer('site_latitude_e5'),
    Column.integer('site_longitude_e5'),
    Column.text('notes'),
    Column.text('buddies_json'),
    Column.text('tags_json'),
    Column.integer('rating'),
    Column.text('conditions'),
    Column.text('divemaster'),
    Column.text('display_deco_algorithm'),
    Column.integer('user_dive_number'),
    // Equipment used on this dive (Phase 3). All optional, free text,
    // surfaced as buddies-style autocompletes in the UI.
    Column.text('suit'),
    Column.text('undersuit'),
    Column.text('weight_system'),
    Column.text('dpv'),
    Column.text('camera'),
    // Subsurface Information-tab parity (env star ratings 1..5, measured
    // temperatures °C, weight-system entries). See migration 0007.
    Column.integer('visibility'),
    Column.integer('wavesize'),
    Column.integer('current'),
    Column.integer('surge'),
    Column.integer('chill'),
    Column.real('air_temp_c'),
    Column.real('water_temp_c'),
    Column.text('weights_json'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  Table('cylinders', [
    Column.text('owner_id'),
    Column.text('label'),
    Column.text('role'),
    Column.integer('bailout_order'),
    Column.real('volume_liters'),
    Column.integer('working_pressure_bar'),
    Column.text('notes'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // Composite PK in Drift (dive_id, cylinder_id); synthetic id =
  // "{dive_id}:{cylinder_id}" upstream. Records the OC bailout cylinders
  // a diver carried on a given dive, with the gas the cylinder held
  // (per-dive — vessels themselves are gas-agnostic).
  Table('dive_bailout_carry', [
    Column.text('owner_id'),
    Column.text('dive_id'),
    Column.text('cylinder_id'),
    Column.text('gas_mix'),
    Column.integer('fill_pressure_bar'),
    Column.integer('bailout_order'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // PK = dive_id (the member dive); dives sharing a `group_id` form one
  // merge group. `group_id` is a deterministic hash of the sorted member
  // dive ids (see generateMergeGroupId), not a pointer to a dive. No
  // `dive_id` column here — PowerSync's implicit `id` IS the dive_id (same
  // trick as dive_samples).
  Table('dive_merge_links', [
    Column.text('owner_id'),
    Column.text('group_id'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // Cylinder analysis log (gas analyzer, issue #111). cylinder_id is a soft
  // reference to cylinders.id (no FK, nullable). mod_ppo2s is a JSON array
  // of the ppO2 limits (bar) the MODs were shown for; the mix label and MOD
  // depths are derived from o2/he, never stored. stable is 0/1.
  // target_o2_percent / target_he_percent are the desired mix in whole
  // percents (null target O2 = none set); gas_role is 'bailout', 'diluent',
  // 'backgas' or 'deco' (null = bailout). Issue #114 (cylinder labels).
  // needs_signoff is 0/1: the entry waits in the log for the diver to sign
  // it off. capture_source is null for a screen save, 'bridge_ok' for a
  // capture made on the SOLO's OK press through the ESP32 bridge and 'usb_ok'
  // for one the app made itself on a USB cable (Log on OK); bridge_record_id
  // is '<bridge>/<rid>'; analysed_for is who the gas is for (free text).
  // Issue #113. is_residual is 0/1: an analysis of what was left in the
  // cylinder before a fill, which closes no blend (issue #112).
  Table('gas_analyses', [
    Column.text('owner_id'),
    Column.text('cylinder_id'),
    Column.text('analysed_by'),
    Column.integer('analysed_at'),
    Column.real('o2_percent'),
    Column.real('he_percent'),
    Column.real('fill_pressure_bar'),
    Column.real('temp_c'),
    Column.real('baro_hpa'),
    Column.text('mod_ppo2s'),
    Column.integer('stable'),
    Column.text('notes'),
    Column.integer('target_o2_percent'),
    Column.integer('target_he_percent'),
    Column.text('gas_role'),
    Column.integer('needs_signoff'),
    Column.text('capture_source'),
    Column.text('bridge_record_id'),
    Column.text('analysed_for'),
    Column.integer('is_residual'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // Texts the diver has accepted (issue #184): subject is e.g.
  // 'planner_warning', text_version the version of that text. Accepted =
  // a live row at the version the app ships. Rows are only ever added.
  Table('user_acknowledgements', [
    Column.text('owner_id'),
    Column.text('subject'),
    Column.integer('text_version'),
    Column.integer('accepted_at'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // Open blends (issue #112): blends logged on the Blend tab and not yet
  // closed by an analysis. closed_by_analysis_id is a soft reference to
  // gas_analyses.id (no FK, nullable). Percents are whole numbers, pressures
  // bar, water_capacity_l litres; gas_role is 'bailout', 'diluent',
  // 'backgas' or 'deco'.
  Table('open_blends', [
    Column.text('owner_id'),
    Column.integer('target_o2_percent'),
    Column.integer('target_he_percent'),
    Column.real('target_pressure_bar'),
    Column.integer('residual_o2_percent'),
    Column.integer('residual_he_percent'),
    Column.real('residual_pressure_bar'),
    Column.integer('topoff_o2_percent'),
    Column.integer('topoff_he_percent'),
    Column.real('water_capacity_l'),
    Column.text('gas_role'),
    Column.text('blended_by'),
    Column.integer('blended_at'),
    Column.text('closed_by_analysis_id'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  Table('oxygen_cells', [
    Column.text('owner_id'),
    Column.integer('slot'),
    Column.text('label'),
    Column.integer('installed_date'),
    Column.integer('retired_date'),
    Column.text('notes'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  Table('scrubber_sessions', [
    Column.text('owner_id'),
    Column.integer('started_date'),
    Column.integer('total_minutes'),
    Column.text('media_type'),
    Column.text('notes'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // Composite PK in Drift (dive_computer_id, channel_index); synthetic
  // id = "{dive_computer_id}:{channel_index}" upstream.
  Table('pressure_mappings', [
    Column.text('owner_id'),
    Column.text('dive_computer_id'),
    Column.integer('channel_index'),
    Column.text('cylinder_id'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // Composite PK in Drift (dive_id, gas_mix_index); synthetic
  // id = "{dive_id}:{gas_mix_index}" upstream.
  Table('dive_cylinders', [
    Column.text('owner_id'),
    Column.text('dive_id'),
    Column.integer('gas_mix_index'),
    Column.text('cylinder_id'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  Table('dive_computers', [
    Column.text('owner_id'),
    Column.integer('serial'),
    Column.integer('model'),
    Column.integer('firmware_version'),
    Column.text('nickname'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  Table('dives', [
    Column.text('owner_id'),
    Column.integer('dc_serial'),
    Column.integer('dc_dive_number'),
    Column.integer('start_time'),
    Column.integer('end_time'),
    Column.integer('utc_offset_minutes'),
    Column.integer('duration_seconds'),
    Column.integer('max_depth_mm'),
    Column.integer('dive_mode'),
    Column.integer('deco_model'),
    Column.integer('gf_low'),
    Column.integer('gf_high'),
    Column.integer('atmospheric_pressure_mbar'),
    Column.integer('water_density'),
    Column.integer('log_version'),
    Column.integer('dc_model'),
    Column.integer('dc_firmware'),
    Column.integer('sample_interval_ms'),
    Column.text('gas_mixes_json'),
    Column.text('tanks_json'),
    Column.text('sensor_calibration_json'),
    Column.integer('configured_stack_seconds'),
    Column.integer('stack_remaining_at_start_seconds'),
    Column.integer('stack_remaining_at_end_seconds'),
    Column.integer('parser_version'),
    Column.integer('imported_at'),
    Column.integer('subsurface_uploaded_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // Per-dive attachments — files in R2 (storage_key) + URL links.
  // `kind` discriminates: file rows have storage_key/mime_type/etc;
  // link rows have url. `parent_kind`/`parent_id` are generic so the
  // same table later carries certification attachments too.
  Table('dive_attachments', [
    Column.text('owner_id'),
    Column.text('parent_kind'),
    Column.text('parent_id'),
    Column.text('kind'),
    Column.text('title'),
    Column.text('description'),
    Column.integer('display_order'),
    Column.text('storage_key'),
    Column.text('mime_type'),
    Column.integer('size_bytes'),
    Column.text('original_filename'),
    Column.text('checksum_sha256'),
    Column.integer('upload_state'),
    Column.integer('upload_attempts'),
    Column.text('url'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // One row per plan: draft row has name IS NULL; named rows are saved
  // plans. Body columns are JSON-encoded (gases/segments/bailout/settings).
  Table('dive_plans', [
    Column.text('owner_id'),
    Column.text('name'),
    Column.text('mode'),
    Column.text('gases_json'),
    Column.text('segments_json'),
    Column.text('bailout_json'),
    Column.text('settings_json'),
    Column.text('notes'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('deleted_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
  // PK = dive_id, 1:1 with dives. Sample blobs are base64 strings.
  Table('dive_samples', [
    Column.text('owner_id'),
    Column.integer('sample_count'),
    Column.text('depth_blob'),
    Column.text('temperature_blob'),
    Column.text('ppo2_blob'),
    Column.text('cell_mv0_blob'),
    Column.text('cell_mv1_blob'),
    Column.text('cell_mv2_blob'),
    Column.text('setpoint_blob'),
    Column.text('cns_blob'),
    Column.text('deco_depth_blob'),
    Column.text('deco_time_blob'),
    Column.text('tts_blob'),
    Column.text('gas_mix_idx_blob'),
    Column.text('status_blob'),
    Column.text('tank_pressures_blob'),
    Column.integer('created_at'),
    Column.integer('updated_at'),
    Column.integer('version'),
    Column.integer('sync_status'),
  ]),
]);
