!*radsxogen -- RADS crossover generator
!+
program radsxogen

! This program "generates" crossovers from RADS data, i.e.,
! it searches crossovers within a batch of passes of altimeter
! data (single satellite crossovers) or between different
! batches of altimeter data (dual satellite crossovers).
!
! The output is a netCDF file containing the crossover times
! and locations of the crossovers, with the information of
! the respective passes. With a consecutive run of radsxosel
! more information can be added to the crossover file.
!-
! $Id$
! Created by Remko Scharroo, Altimetrics LLC, based in part on previous
! programs, max and max2, developed at DEOS.
!-----------------------------------------------------------------------
use rads
use netcdf
use rads_netcdf
use rads_misc

integer(fourbyteint), parameter :: msat = 10, vbase = 13, mtrk = 500000
real(eightbytereal) :: dt(msat) = -1d0
type(rads_sat) :: S(msat)
integer(fourbyteint) :: i, j, nsat = 0, nsel = 0, reject = -1, ios, debug, ncid, dimid(3), start(2), varid(vbase)
logical :: duals = .true., singles = .true., l
character(len=80) :: arg, filename = 'radsxogen.nc'
character(len=1) :: interpolant = 'q'
type :: nr_
	integer :: test, shallow, xdat, ins, gap, xdt, xout, trk
endtype
type(nr_) :: nr
type :: trk_
	real(eightbytereal) :: equator_lon, equator_time, start_time, end_time
	integer(twobyteint) :: nr_alt, nr_xover, satid, cycle, pass
endtype
type(trk_) :: trk(mtrk)
integer(fourbyteint), allocatable :: selid(:), key(:), idx(:), trkid(:,:)

! Initialize RADS or issue help
call synopsis
S%sat = '' ! Initialize blank
S%error = rads_noerr
call rads_init (S)
if (any(S%error /= rads_noerr)) call rads_exit ('Fatal error')
dt(1) = 0.5d0

! Start with this-is message
l = rads_version ('$Revision$')

! If no sat= is given, exit
if (S(1)%sat == '') call rads_exit ('Need at least one sat= option')

! Determine how many satellites and cycles.
! Also check that the same number of variables have been selected for each satellite
do i = 1,msat
	if (S(i)%sat == '') exit
	if (S(i)%nsel == 0) call rads_parse_varlist (S(i), 'sla')
	if (S(i)%nsel /= S(1)%nsel) call rads_exit ('Unequal amount of variables on sel= for different satellites')
	nsat = i
enddo
nsel = S(1)%nsel
debug = maxval(S(1:nsat)%debug)

! Scan command line arguments
do i = 1,iargc()
	call getarg (i,arg)
	if (arg(:2) == '-rn') then
		reject = -2
	else if (arg(:2) == '-r') then
		reject = 0
		read (arg(3:),*,iostat=ios) reject
	else if (arg(:2) == '-s') then
		duals = .false.
	else if (arg(:2) == '-d') then
		singles = .false.
	else if (arg(:2) == '-i') then
		interpolant = arg(3:3)
		if (interpolant == 'L') interpolant = 'l'
		if (interpolant == 'C') interpolant = 'c'
		if (interpolant == 'Q') interpolant = 'q'
	else if (arg(:3) == 'dt=') then
		read (arg(4:),*,iostat=ios) dt
	endif
enddo

! Get the file name (last argument not to start with - or contain =)
do i = iargc(),1,-1
	call getarg (i,arg)
	if (arg(1:1) /= '-' .and. index(arg,'=') <= 0) then
		filename = arg
		exit
	endif
enddo

! Set all unspecified dt equal to the previous
do i = 2,nsat
	if (dt(i) < 0d0) dt(i) = dt(i-1)
enddo

! If SLA is among the results, remember which index that is
do i = 1,nsel
	if (S(1)%sel(i)%info%datatype == rads_type_sla) then
		if (reject == -1) reject = i
	endif
enddo

! Write info about this job
if (nsat == 1) duals = .false.
write (*, '(/"Output file name: ", a)') trim(filename)
if (singles .and. duals) then
	write (*, '("Processing single and dual satellite crossovers")')
else if (singles) then
	write (*, '("Processing single satellite crossovers")')
else if (duals) then
	write (*, '("Processing dual satellite crossovers")')
else
	write (*, '("No single or duals satellite crossovers are processed. Aborting.")')
	stop
endif
write (*, '(/"Satellite  Cycles    Passes  Delta-time cutoff (days)")')
do i = 1,nsat
	write (*, '(a,i5,i4,2i5,f8.3)') S(i)%satellite, S(i)%cycles(1:2), S(i)%passes(1:2), dt_days(S(i),dt(i))
enddo

! Do further initialisations
nr = nr_ (0, 0, 0, 0, 0, 0, 0, 0)
allocate (selid(nsel))

! Open output netCDF file
call nfs (nf90_create (filename, nf90_write, ncid))
call nfs (nf90_def_dim (ncid, 'sat', 2, dimid(1)))
call nfs (nf90_def_dim (ncid, 'xover', nf90_unlimited, dimid(2)))
call def_var_sel (ncid, S(1)%lat, dimid(2:2), varid(1))
call def_var_sel (ncid, S(1)%lon, dimid(2:2), varid(2))
call def_var_sel (ncid, S(1)%time, dimid(1:2), varid(3))
call def_var (ncid, 'track', 'track number', '', nf90_int4, dimid(1:2), varid(4))
do i = 1,nsel
	call def_var_sel (ncid, S(1)%sel(i), dimid(1:2), selid(i))
enddo
call nfs (nf90_enddef (ncid))

! We are now ready to compare the different batches of passes
do i = 1,nsat
	do j = i,nsat
		call xogen_batch (S(i), S(j), dt(i), dt(j))
	enddo
enddo

! Print statistics
write (*, 500) nr
500 format (/ &
'Number of crossings tested :',i9/ &
'- Shallow crossings        :',i9/ &
'- Too few data on pass     :',i9/ &
'- No intersection          :',i9/ &
'- Too few data around xover:',i9/ &
'- Too large time difference:',i9/ &
'= Number crossovers written:',i9/ &
'Number of tracks           :',i9/)

call rads_stat (S)

if (nr%trk == 0) then
	call nfs (nf90_close (ncid))
	stop
endif

! Sort the track information in order satid/cycle/pass
allocate (key(nr%trk), idx(nr%trk), trkid(2,nr%xout))
forall (i = 1:nr%trk)
	idx(i) = i
	key(i) = trk(i)%satid * 10000000 + trk(i)%cycle * 10000 + trk(i)%pass
endforall
call iqsort (idx, key, nr%trk)

! Add the track info to the netCDF file
call nfs (nf90_redef (ncid))
call nfs (nf90_def_dim (ncid, 'track', nr%trk, dimid(3)))
call def_var (ncid, 'satid', 'satellite id', '', nf90_int1, dimid(3:3), varid(5))
call def_var (ncid, 'cycle', 'cycle number', '', nf90_int2, dimid(3:3), varid(6))
call def_var (ncid, 'pass', 'pass number', '', nf90_int2, dimid(3:3), varid(7))
call def_var (ncid, 'equator_lon', 'longitude of equator crossing', 'degrees east', nf90_double, dimid(3:3), varid(8))
call def_var (ncid, 'equator_time', 'time of equator crossing', S(1)%time%info%units, nf90_double, dimid(3:3), varid(9))
call def_var (ncid, 'start_time', 'start time of track', S(1)%time%info%units, nf90_double, dimid(3:3), varid(10))
call def_var (ncid, 'end_time', 'end time of track', S(1)%time%info%units, nf90_double, dimid(3:3), varid(11))
call def_var (ncid, 'nr_xover', 'number of crossovers along track', '', nf90_int2, dimid(3:3), varid(12))
call def_var (ncid, 'nr_alt', 'number of measurements along track', '', nf90_int2, dimid(3:3), varid(13))
call nfs (nf90_enddef (ncid))

call nfs (nf90_put_var (ncid, varid( 5), trk(idx)%satid))
call nfs (nf90_put_var (ncid, varid( 6), trk(idx)%cycle))
call nfs (nf90_put_var (ncid, varid( 7), trk(idx)%pass))
call nfs (nf90_put_var (ncid, varid( 8), trk(idx)%equator_lon))
call nfs (nf90_put_var (ncid, varid( 9), trk(idx)%equator_time))
call nfs (nf90_put_var (ncid, varid(10), trk(idx)%start_time))
call nfs (nf90_put_var (ncid, varid(11), trk(idx)%end_time))
call nfs (nf90_put_var (ncid, varid(12), trk(idx)%nr_xover))
call nfs (nf90_put_var (ncid, varid(13), trk(idx)%nr_alt))

! Renumber the track number for the xover data
forall (i = 1:nr%trk)
	key(idx(i)) = i	! key becomes the inverse of idx
endforall
call nfs (nf90_get_var (ncid, varid(4), trkid))
trkid(1,:) = key(trkid(1,:))
trkid(2,:) = key(trkid(2,:))
call nfs (nf90_put_var (ncid, varid(4), trkid))
deallocate (key, idx, trkid)

call nfs (nf90_close (ncid))

call rads_end (S)

contains

!***********************************************************************

subroutine synopsis
if (rads_version ('$Revision$','Generate altimeter crossovers from RADS')) return
call rads_synopsis()
write (0,1300)
1300 format (/ &
'Program specific [program_options] are:'/ &
'  -d                : do dual satellite crossovers only'/ &
'  -s                : do single satellite crossovers only'/ &
'  -i[l|c|q|p]       : interpolate values to crossover by linear interpolation, cubic spline'/ &
'                      quadratic polynomial fit (default) or cubic polynomial fit'/ &
'  -r#               : reject xovers if data item number # on sel= specifier is NaN'/ &
'                      (default: reject if SLA field is NaN)'/ &
'  -r0, -r           : do not reject xovers with NaN values'/ &
'  -rn               : reject xovers if any value is NaN'/ &
'  dt=fraction       : limit crossover time interval to fraction of repeat cycle (default: 0.5)'/ &
'                      use negative number to specify interval in days'/ &
'  filename          : specify output filename (default: radsxogen.nc)')
stop
end subroutine synopsis

!***********************************************************************
! Function to convert time interval to days

function dt_days (S, dt)
type(rads_sat), intent(in) :: S
real(eightbytereal), intent(in) :: dt
real(eightbytereal) :: dt_days
if (dt < 0d0) then
	dt_days = -dt
else
	dt_days = dt * S%phase%repeat_days
endif
end function dt_days

!***********************************************************************
! Define variables for the output file

subroutine def_var (ncid, var, long_name, units, nctype, dimid, varid)
use netcdf
use rads_netcdf
integer(fourbyteint), intent(in) :: ncid, nctype, dimid(:)
character(len=*), intent(in) :: var, long_name, units
integer(fourbyteint), intent(out) :: varid
call nfs (nf90_def_var (ncid, trim(var), nctype, dimid, varid))
call nfs (nf90_put_att (ncid, varid, 'long_name', trim(long_name)))
if (units /= '') call nfs (nf90_put_att (ncid, varid, 'units', trim(units)))
end subroutine def_var

subroutine def_var_sel (ncid, sel, dimid, varid)
use netcdf
use rads_netcdf
integer(fourbyteint), intent(in) :: ncid, dimid(:)
type(rads_var), intent(in) :: sel
integer(fourbyteint), intent(out) :: varid
type(rads_varinfo), pointer :: info
integer(fourbyteint) :: e
info => sel%info
call nfs(nf90_def_var(ncid, sel%name, info%nctype, dimid, varid))
e = nf90_put_att (ncid, varid, 'long_name', trim(info%long_name))
if (info%standard_name /= '') e = e + nf90_put_att (ncid, varid, 'standard_name', trim(info%standard_name))
if (info%source /= '') e = e + nf90_put_att (ncid, varid, 'source', trim(info%source))
if (info%units /= '') e = e + nf90_put_att (ncid, varid, 'units', trim(info%units))
if (info%scale_factor /= 1d0) e = e + nf90_put_att (ncid, varid, 'scale_factor', info%scale_factor)
if (info%add_offset /= 0d0)  e = e + nf90_put_att (ncid, varid, 'add_offset', info%add_offset)
if (info%datatype < rads_type_time) e = e + nf90_put_att (ncid, varid, 'coordinates', 'lon lat')
if (info%source /= '') e = e + nf90_put_att (ncid, varid, 'source', trim(info%source))
if (info%standard_name /= '') e = e + nf90_put_att (ncid, varid, 'standard_name', trim(info%standard_name))
if (info%comment /= '') e = e + nf90_put_att (ncid, varid, 'comment', trim(info%comment))
if (e > 0) write (*,*) 'Error writing attributes for variable '//trim(sel%name)
end subroutine def_var_sel

!***********************************************************************
! Batch process passes selected for satellites S1 and S2 (which could be the same).
! Passes of satellite S1 are cycled through (opened and closed) in order.
! Passes of satellite S2 are held in memory until no longer needed, but still processed in order.

subroutine xogen_batch (S1, S2, dt1, dt2)
type(rads_sat), intent(inout) :: S1, S2
real(eightbytereal), intent(in) :: dt1, dt2
integer(fourbyteint) :: cycle1, pass1, cycle2, pass2, step
type(rads_pass) :: P1
type(rads_pass), pointer :: P2, top, prev
real(eightbytereal) :: t0, t1, t2, t3, dt

! Skip singles or duals when they are not wanted
! If singles, match only ascending and descending, hence step = 2
if (S1%sat == S2%sat) then
	if (.not.singles) return
	step = 2
else
	if (.not.duals) return
	step = 1
endif

! See if there is any chance of a temporal overlap between S1 and S2
dt = min (dt_days(S1,dt1), dt_days(S2,dt2)) * 86400d0
t0 = rads_cycle_to_time (S1, S1%cycles(1)) - dt
t1 = rads_cycle_to_time (S1, S1%cycles(2)) + S1%phase%repeat_days * 86400d0 + dt
t2 = rads_cycle_to_time (S2, S2%cycles(1))
t3 = rads_cycle_to_time (S2, S2%cycles(2)) + S2%phase%repeat_days * 86400d0
if (t0 > t3 .or. t1 < t2) return

! Initialize pass and cycle numbers of S2
! Base the starting cycle number for S2 on the start time of the first cycle of S1
pass2 = S2%passes(1) - 1
cycle2 = max(S2%cycles(1), rads_time_to_cycle (S2, t0))

! Nullify all pointers
nullify (P2, top, prev)

! Cycle through cycles and passes for S1
do cycle1 = S1%cycles(1), S1%cycles(2)
	do pass1 = S1%passes(1), S1%passes(2), step

		! Open a pass for S1, to be crossed with any pass of S2
		call rads_open_pass (S1, P1, cycle1, pass1)
		if (P1%ndata <= 0) then
			if (debug > 2) write (*,*) 'empty',P1%cycle,P1%pass
			call rads_close_pass (S1, P1)
			cycle
		endif
		call load_data (S1, P1)

		! Limit the time selection for P2 based on the time limits of P1
		t0 = P1%start_time - dt
		t1 = P1%end_time   + dt

		! Walk through a linked list of already loaded passes
		P2 => top
		do while (associated(P2))
			if (P2%end_time < t0) then ! Release passes that are far in the past
				top => P2%next ! Reassign the top of the list to the next pass (if any)
				nullify (prev)
				if (debug > 2) write (*,*) 'release',P2%cycle,P2%pass
				call rads_close_pass (S2, P2)
				deallocate (P2)
				P2 => top
			else if (P2%start_time > t1) then ! Do not consider (yet) passes in the far future
				exit
			else ! Cross P1 and P2 if P2 holds any data
				if (P2%ndata > 0) call xogen_passes (S1, P1, S2, P2, dt)
				pass2 = P2%pass
				cycle2 = P2%cycle
				prev => P2
				P2 => P2%next
			endif
		enddo

		! Now load new passes within the time range
		do while (.not.associated(P2))
			pass2 = pass2 + step
			if (pass2 > S2%passes(2) .or. pass2 > S2%phase%passes(2)) then ! Wrap to next cycle
				cycle2 = cycle2 + 1
				if (cycle2 > S2%cycles(2)) exit
				pass2 = S2%passes(1) - 1 + step ! Start with pass "1" or "2"
			endif
			allocate (P2)
			if (debug > 2) write (*,*) 'open',cycle2,pass2
			call rads_open_pass (S2, P2, cycle2, pass2)
			if (P2%end_time < t0) then
				if (debug > 2) write (*,*) 'release',P2%cycle,P2%pass
				call rads_close_pass (S2, P2)
				deallocate (P2)
				cycle
			endif
			if (associated(prev)) then ! Append to linked list
				prev%next => P2
			else ! Start new linked list
				top => P2
			endif
			call load_data (S2, P2)
			if (P2%start_time > t1) exit
			if (P2%ndata > 0) call xogen_passes (S1, P1, S2, P2, dt)
			! Point to next (empty) slot
			prev => P2
			P2 => P2%next
		enddo

		! Clear any memory of pass P1
		call rads_close_pass (S1, P1)
	enddo
enddo

! Dump remaining open passes

do while (associated(top))
	P2 => top
	if (debug > 2) write (*,*) 'release',P2%cycle,P2%pass
	call rads_close_pass (S2, P2)
	top => P2%next
	deallocate (P2)
enddo
end subroutine xogen_batch

!***********************************************************************
! Load the data for a pass, remove invalids, store it back into an
! expanded P%tll.

subroutine load_data (S, P)
type(rads_sat), intent(inout) :: S
type(rads_pass), intent(inout) :: P
real(eightbytereal), pointer :: data(:,:), tll(:,:)
real(eightbytereal) :: x
integer(fourbyteint) :: i
logical, allocatable :: keep(:)

if (P%ndata == 0) return

! Allocate enough memory for the data and get all of it
allocate (data(P%ndata,nsel),keep(P%ndata))
do i = 1,nsel
	call rads_get_var (S, P, S%sel(i), data(:,i))
enddo

! Determine which records are kept
if (reject < 0) then	! Reject if any is NaN
	forall (i=1:P%ndata)
		keep(i) = .not.any(isnan(data(i,:)))
	endforall
else if (reject > 0) then
	keep = .not.isnan(data(:,reject))
else
	keep = .true.
endif

! Create new tll array with only kept records, expanded with all data fields
P%ndata = count(keep)
if (P%ndata == 0) return
allocate (tll(P%ndata,nsel+3))
forall (i=1:3)
	tll(:,i) = pack (P%tll(:,i),keep)
endforall
forall (i=1:nsel)
	tll(:,i+3) = pack (data(:,i),keep)
endforall

! Group all longitudes to within 180 degrees of the equator crossing longitude
x = P%equator_lon - 180d0
tll(:,3) = modulo (tll(:,3) - x, 360d0) + x

! Get rid of old tll array and replace it with the new one
deallocate (P%tll,data,keep)
P%tll => tll

! Store track info
nr%trk = nr%trk + 1
if (nr%trk > mtrk) stop 'Too many tracks'
trk(nr%trk) = trk_ (P%equator_lon, P%equator_time, tll(1,1), tll(P%ndata,1), P%ndata, 0, S%satid, P%cycle, P%pass)
P%trkid = nr%trk

! Close the pass file, but keep all its info
call rads_close_pass (S, P, .true.)
end subroutine load_data

!***********************************************************************
! Compute the intersection of pass P1 of satellite S1 and pass P2 of satellite S2.

subroutine xogen_passes (S1, P1, S2, P2, dt)
type(rads_sat), intent(inout) :: S1, S2
type(rads_pass), intent(inout) :: P1, P2
real(eightbytereal), intent(in) :: dt
real(eightbytereal) :: shiftlon, x, y, t1, t2
real(eightbytereal), allocatable :: data(:,:)
integer :: i, i1, i2, j1, j2, k1, k2
type(rads_varinfo), pointer :: info

! Count number of calls
nr%test = nr%test + 1

! If inclinations of S1 and S2 differ less than 1 degree, match only ascending and descending passes
if (abs(S1%inclination - S2%inclination) < 1d0 .and. modulo(P1%pass - P2%pass, 2) == 0) then
	nr%shallow = nr%shallow + 1
	return
endif

! If there are fewer than 2 points on either pass, then there is no crossing
if (P1%ndata < 2 .or. P2%ndata < 2) then
	nr%xdat = nr%xdat + 1
	return
endif

! Determine if the tracks have common latitude
if (min(P1%tll(1,2), P1%tll(P1%ndata,2)) > max(P2%tll(1,2), P2%tll(P2%ndata,2)) .or. &
	max(P1%tll(1,2), P1%tll(P1%ndata,2)) < min(P2%tll(1,2), P2%tll(P2%ndata,2))) then
	nr%ins = nr%ins + 1
	return
endif

! Determine a longitude shift for the second pass to make it closer than 180 degrees from the first
if (P2%equator_lon - P1%equator_lon > 180d0) then
	shiftlon = -360d0
else if (P2%equator_lon - P1%equator_lon < -180d0) then
	shiftlon = 360d0
else
	shiftlon = 0d0
endif

if (debug > 2) then
	write (*,*) 'processing',P1%cycle,P1%pass,P2%cycle,P2%pass
	write (*,*) 'equator',P1%equator_lon,P2%equator_lon,shiftlon
	write (*,*) 'x-ranges',P1%tll(1,3),P1%tll(P1%ndata,3),P2%tll(1,3)+shiftlon,P2%tll(P2%ndata,3)+shiftlon
endif

! Determine if the passes have common longitudes
if (min(P1%tll(1,3), P1%tll(P1%ndata,3)) > max(P2%tll(1,3), P2%tll(P2%ndata,3))+shiftlon .or. &
	max(P1%tll(1,3), P1%tll(P1%ndata,3)) < min(P2%tll(1,3), P2%tll(P2%ndata,3))+shiftlon) then
	nr%ins = nr%ins + 1
	return
endif

! Use a modified sweep-line algorithm to look for intersections
call sweep_line (P1%tll(:,3), P1%tll(:,2), P1%tll(:,1), P2%tll(:,3)+shiftlon, P2%tll(:,2), P2%tll(:,1), &
	i1, j1, i2, j2, x, y, t1, t2)
if (i1 == 0) then ! No crossing
	nr%ins = nr%ins + 1
	return
endif

! Move x back to proper range
if (x < S1%lon%info%limits(1)) x = x + 360d0
if (x > S1%lon%info%limits(2)) x = x - 360d0

if (debug > 2) then
	write (*,*) 'time',P1%tll(i1,1),t1,P1%tll(j1,1),P2%tll(i2,1),t2,P2%tll(j2,1)
	write (*,*) 'lat ',P1%tll(i1,2),y ,P1%tll(j1,2),P2%tll(i2,2),y ,P2%tll(j2,2)
	write (*,*) 'lon ',P1%tll(i1,3),x ,P1%tll(j1,3),P2%tll(i2,3),x ,P2%tll(j2,3)
endif

! See if time interval exceeds limits
if (abs(t1-t2) <= dt) then
	! Continue only for small time interval, not if NaN
else
	nr%xdt = nr%xdt + 1
	return
endif

! For the later interpolation of the variables along-track we will use 6 points, 3 on each side
! of the crossover. The furthest points have to be within max_gap 1Hz-intervals, the nearest within
! max_gap/4 1Hz-intervals.
k1 = min(i1, j1) - 2	! Indices of first of 6 points for interpolation
k2 = min(i2, j2) - 2
if (large_gap (S1, P1, k1) .or. large_gap (S2, P2, k2)) then
	nr%gap = nr%gap + 1
	return
endif

! Interpolate data along each track
allocate (data(2,nsel))
call interpolate (t1, P1%tll(k1:k1+5,:), data(1,:))
call interpolate (t2, P2%tll(k2:k2+5,:), data(2,:))

! Write the data to file
nr%xout = nr%xout + 1
trk(P1%trkid)%nr_xover = trk(P1%trkid)%nr_xover + 1
trk(P2%trkid)%nr_xover = trk(P2%trkid)%nr_xover + 1
start = (/ 1, nr%xout /)
call nfs (nf90_put_var (ncid, varid(1), nint4(y / S1%lat%info%scale_factor), start(2:2)))
call nfs (nf90_put_var (ncid, varid(2), nint4(x / S1%lon%info%scale_factor), start(2:2)))
call nfs (nf90_put_var (ncid, varid(3), (/ t1, t2 /), start))
call nfs (nf90_put_var (ncid, varid(4), (/ P1%trkid, P2%trkid /), start))
do i = 1,nsel
	info => S1%sel(i)%info
	select case (info%nctype)
	case (nf90_int1)
		call nfs (nf90_put_var (ncid, selid(i), nint1((data(1:2,i) - info%add_offset) / info%scale_factor), start))
	case (nf90_int2)
		call nfs (nf90_put_var (ncid, selid(i), nint2((data(1:2,i) - info%add_offset) / info%scale_factor), start))
	case (nf90_int4)
		call nfs (nf90_put_var (ncid, selid(i), nint4((data(1:2,i) - info%add_offset) / info%scale_factor), start))
	case default
		call nfs (nf90_put_var (ncid, selid(i), (data(1:2,i) - info%add_offset) / info%scale_factor, start))
	end select
enddo
deallocate (data)

end subroutine xogen_passes

!***********************************************************************
! Interpolate the data to the crossover along the track

subroutine interpolate (t, tll, xoval)
real(eightbytereal), intent(in) :: t, tll(:,:)
real(eightbytereal), intent(out) :: xoval(:)
integer(fourbyteint) :: i
integer(fourbyteint), parameter :: m = 6, n = 4, mw = 6*n + 2*m
real(eightbytereal) :: xc, x(m), y(m,nsel), ss(n), cf(n), work(mw), aa(m), v1(m), vn(m), cc(m), d(m), f1

! x = time, y = data value
! Reduce time and values to numbers relative to the third point
x = tll(:,1) - tll(3,1)
xc = t - tll(3,1)
forall (i = 1:nsel)
	y(:,i) = tll(:,3+i) - tll(3,3+i)
endforall

if (interpolant == 'l') then	! Linear interpolation
	xoval = xc * y(4,:) / x(4)
else if (interpolant == 'c') then	! Cubic spline interpolation
	do i = 1,nsel
		call e02baf(m,-1,y(:,i),aa,x,xc,xoval(i),f1,v1,vn,cc,d)
		call e02baf(m,-2,y(:,i),aa,x,xc,xoval(i),f1,v1,vn,cc,d)
	enddo
else if (interpolant == 'q') then	! Quadratic polynomial fit
	do i = 1,nsel
		call e02adf(x,y(:,i),m,3,ss,cf,work)
		xoval(i) = cf(1)+xc*(cf(2)+xc*cf(3))
	enddo
else	! Cubic polynomial fit
	do i = 1,nsel
		call e02adf(x,y(:,i),m,4,ss,cf,work)
		xoval(i) = cf(1)+xc*(cf(2)+xc*(cf(3)+xc*cf(4)))
	enddo
endif
xoval = xoval + tll(3,4:)
end subroutine interpolate

!***********************************************************************
! Determine if gap between nearest points to the crossover or furthest of six points is too large

function large_gap (S, P, k)
type(rads_sat), intent(in) :: S
type(rads_pass), intent(in) :: P
integer(fourbyteint), intent(in) :: k
logical :: large_gap
integer, parameter :: max_gap = 12
large_gap = (k < 1 .or. k+5 > P%ndata .or. &
	nint((P%tll(k+5,1) - P%tll(k,1)) / S%dt1hz) > max_gap .or. &
	nint(abs(P%tll(k+2,1) - P%tll(k+3,1)) / S%dt1hz) > max_gap/4)
end function large_gap

!***********************************************************************
! This is a modified type of sweep-line algorithm to determine whether two
! line segments cross, and if so, at what indices.
! x1 and x2 need to be continuously increasing or decreasing.
! Upon return i1,j1 and i2,j2 are the indices of the two sides of the intervals
! at which the lines intersect, or 0 when there is no intersection.
! The returned values xc,yc are the coordinates of the crossover computed
! by crossing two spherical arcs through the end points.
! The times of the crossovers for the two passes are tc1 and tc2.

subroutine sweep_line (x1, y1, t1, x2, y2, t2, i1, j1, i2, j2, xc, yc, tc1, tc2)
real(eightbytereal), intent(in) :: x1(:), y1(:), t1(:), x2(:), y2(:), t2(:)
integer, intent(out) :: i1, j1, i2, j2
real(eightbytereal), intent(out) :: xc, yc, tc1, tc2
integer(fourbyteint) :: n1, n2, d1, d2
n1 = size(x1)
n2 = size(x2)
if (x1(2) > x1(1)) then
	i1 = 1
	d1 = 1
else
	i1 = n1
	d1 = -1
endif
if (x2(2) > x2(1)) then
	i2 = 1
	d2 = 1
else
	i2 = n2
	d2 = -1
endif
! i1,i2 are the indices of the left sides of the segments
! j1,j2 are the indices of the right sides of the segments
! d1,d2 are the directions of advance (-1 or +1) making x increase
do
	j1 = i1 + d1
	j2 = i2 + d2
	if (j1 < 1 .or. j1 > n1 .or. j2 < 1 .or. j2 > n2) exit
	! The lines certainly do not cross when the x-ranges do not overlap, so make sure of that first
	if (x1(j1) < x2(i2)) then
		i1 = j1
		cycle
	else if (x2(j2) < x1(i1)) then
		i2 = j2
		cycle
	endif
	if (intersect(x1(i1),y1(i1),t1(i1),x1(j1),y1(j1),t1(j1),x2(i2),y2(i2),t2(i2),x2(j2),y2(j2),t2(j2),xc,yc,tc1,tc2)) then
		if (debug > 2) write (*,*) 'crossing',i1,j1,i2,j2,xc,yc,tc1,tc2
		return
	endif

	! Move the leftmost interval further to the right
	if (x1(j1) < x2(j2)) then
		i1 = j1
	else
		i2 = j2
	endif
enddo
if (debug > 2) write (*,*) 'no crossing'
i1 = 0
i2 = 0
j1 = 0
j2 = 0
xc = 0d0
xc = xc / xc
yc = xc
end subroutine sweep_line

!***********************************************************************
! Does the line from (x1,y1) via (x2,y2) to (x3,y3) go counter-clockwise?

function ccw (x1, y1, x2, y2, x3, y3)
real(eightbytereal), intent(in) :: x1, y1, x2, y2, x3, y3
logical ccw
ccw = ((x2-x1) * (y3-y1) > (y2-y1) * (x3-x1))
end function ccw

!***********************************************************************
! The lines between two consecutive points on line 1 and line 2 intersect when neither combination
! of 3 points goes both clockwise or both counter-clockwise

function intersect (x11, y11, t11, x12, y12, t12, x21, y21, t21, x22, y22, t22, xc, yc, tc1, tc2)
use rads_misc
real(eightbytereal), intent(in) :: x11, y11, t11, x12, y12, t12, x21, y21, t21, x22, y22, t22
real(eightbytereal), intent(out) :: xc, yc, tc1, tc2
real(eightbytereal) :: v11(3), v12(3), v21(3), v22(3), vc(3)
logical :: intersect
if (ccw(x11,y11,x21,y21,x22,y22) .eqv. ccw(x12,y12,x21,y21,x22,y22)) then
	intersect = .false.
else if (ccw(x21,y21,x11,y11,x12,y12) .eqv. ccw(x22,y22,x11,y11,x12,y12)) then
	intersect = .false.
else
	intersect = .true.
	! Convert longitude and latitude of the end points to vectors
	v11 = xy2v (x11,y11)
	v12 = xy2v (x12,y12)
	v21 = xy2v (x21,y21)
	v22 = xy2v (x22,y22)
	! Let v1 and v2 be vectors perpendicular to planes through arcs 1 and 2
	! The cross product of v1 and v2 points to the crossing point, which we convert back to longitude and latitude
	vc = cross_product (cross_product (v11, v12), cross_product (v21, v22))
	call v2xy (vc, xc, yc)
	! The result may be pointing the opposite direction to what is intended
	if (dot_product(vc,v11) < 0d0) vc = -vc
	! Compute the times of the crossing points using proportionalities
	tc1 = acos(dot_product(vc,v11)) / acos(dot_product(v11,v12)) * (t12-t11) + t11
	tc2 = acos(dot_product(vc,v21)) / acos(dot_product(v21,v22)) * (t22-t21) + t21
endif
end function intersect

!***********************************************************************

function xy2v (x, y) result (v)
real(eightbytereal), intent(in) :: x, y
real(eightbytereal) :: v(3)
v(1) = cos(x*rad)
v(2) = sin(x*rad)
v(1:2) = v(1:2) * cos(y*rad)
v(3) = sin(y*rad)
end function xy2v

!***********************************************************************

subroutine v2xy (v, x, y)
real(eightbytereal), intent(inout) :: v(3)
real(eightbytereal), intent(out) :: x, y
real(eightbytereal) :: c
c = sqrt(sum(v*v))
v = v / c
x = atan2(v(2),v(1)) / rad
y = asin(v(3)) / rad
end subroutine v2xy

!***********************************************************************

end program radsxogen
