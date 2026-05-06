/// PowerSync schema for the seven sync-eligible tables.
///
/// Mirrors the Postgres tables in `supabase/migrations/0001_initial_schema.sql`.
/// PowerSync auto-adds `id text not null primary key` per table, so the
/// schemas below list every other column. JSONB columns become `Column.text`
/// (encode/decode in Dart). Timestamps are millis-since-epoch in `Column.integer`.
///
/// Composite-PK Drift tables synthesize their `id` client-side:
///   - `pressure_mappings.id` = `"<dive_computer_id>:<channel_index>"`
///   - `dive_cylinders.id`    = `"<dive_id>:<gas_mix_index>"`
/// The cloud Postgres schema enforces uniqueness on the underlying composite.
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
]);
