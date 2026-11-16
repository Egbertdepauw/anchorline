-- Makes the guard scenario's data pass the 0027 guard: removes B's
-- cross-owner bailout-carry row, which has no parent of the same owner. A's
-- dive and both cylinders stay. Run as postgres, before 0027.
delete from public.dive_bailout_carry where id = 'd1:cyl_b';
