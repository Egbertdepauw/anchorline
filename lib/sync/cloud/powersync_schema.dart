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
    Column.text('gas_mix'),
    Column.text('notes'),
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
