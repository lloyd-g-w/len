-- Pen-to-pixel latency of the low-latency overlay and of Flutter (docs/INK_LAB.md,
-- "Low-latency ink"): trace_processor_shell -q latency.sql trace.pftrace
-- Event times in the len.* markers are CLOCK_MONOTONIC; trace time is BOOTTIME.
create perfetto table off as select b.clock_value - m.clock_value o from clock_snapshot b join clock_snapshot m using(snapshot_id) where b.clock_id=6 and m.clock_id=3 limit 1;
create perfetto table sb as select ts from slice where name like 'setBuffer %SurfaceView[dev.len.len%';
create perfetto table df as select ts, ts+dur pres from actual_frame_timeline_slice where layer_name is null;
create perfetto table pb as select ts from slice where name like 'publishMotionEvent(inputChannel=%dev.len.len%';
create perfetto table pr as select s.ts, cast(substr(s.name,14) as int) + (select o from off) ev from slice s where s.name like 'len.progress %';
create perfetto table fl as select pr.ts, pr.ev, (select min(pres) from df where df.ts >= (select min(ts) from sb where sb.ts > pr.ts)) pres from pr;
create perfetto table wd as select s.ts, cast(substr(s.name,13) as int) + (select o from off) ev from slice s where s.name like 'len.wetDone %' and cast(substr(s.name,13) as int) > 0;
create perfetto table m as
  select 'A overlay: event->written' k, ts - ev v from wd
  union all select 'B overlay: arrival->written', ts - (select max(p.ts) from pb p where p.ts <= wd.ts) from wd
  union all select 'C flutter: event->present', pres - ev from fl where pres is not null
  union all select 'D flutter: progress->present', pres - ts from fl where pres is not null;
create perfetto table r as select k, v, row_number() over (partition by k order by v) i, count(*) over (partition by k) n from m;
select k, n, round(max(case when i = n/2 then v end)/1e6,1) p50, round(max(case when i = n*9/10 then v end)/1e6,1) p90, round(max(case when i = n*99/100 then v end)/1e6,1) p99, round(max(v)/1e6,1) mx from r group by k;
