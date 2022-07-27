!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! File warmLP.f90: adapted from qsolveME to solve FVA in quad-precision with warm-start
! Double-precision version
!
! subroutine warmLP : adapted from qsolveME.f90 and qsolveLP.f90 by Ding Ma
!                      and Michael A. Saunders, to interface with Python
!
! Laurence Yang, SBRG, UCSD
!
! How to generate python extension module via f2py, and use from python:
!   0) [prerequisite] make qminos using -fPIC compiler flag.
!      Otherwise, will get error at step 2) about requiring the -fPIC flag

!   1) Generate signature file, qwarmLP.pyf:
!      f2py -m qwarmLP -h qwarmLP.pyf qwarmLP.f90
!
!   2) Compile with qminos library linked, and generate .so file to import into python:
!      f2py -c qwarmLP.pyf qwarmLP.f90 -L/home/laurence/Software/qminos1114/qminos56/lib -lquadminos
!
!   3) From python:
!      import qwarmLP
!      import numpy as np
!      inform = np.array(0)     # gets modified by qsolveme: in/output exit flag
!      mu0 = 0.1
!      x = qwarmLP.qwarmlp(inform, mu0, probname, M, nncon, nnJac, neJac, ha,
!      ka, ad, bl, bu, nb, N, ne)
!
! 13 Aug 2015: first version.
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


subroutine warmLP(xn,pi,rc, inform, nb, Probname, m, n, ne, &
    ha, ka, ad, bld, bud, hs, warm, &
    nStrOpts, nIntOpts, nRealOpts, stropts, intopts, realopts, intvals, realvals)
  ! all allocatable arrays passed to minoss are stored here

  implicit none

  integer, parameter        :: ip = 4, dp = 8
  ! Pass options directly instead of using specs file
  integer(ip), intent(in)                               :: nStrOpts
  integer(ip), intent(in)                               :: nIntOpts
  integer(ip), intent(in)                               :: nRealOpts
  character(len=72), dimension(nStrOpts), intent(in)    :: stropts
  character(len=55), dimension(nIntOpts), intent(in)    :: intopts
  character(len=55), dimension(nRealOpts),intent(in)    :: realopts
  integer(ip), dimension(nIntOpts), intent(in)          :: intvals
  ! Real options input as real(8)
  real(dp), dimension(nRealOpts), intent(in)            :: realvals

  ! qMINOS common block
  real(dp)        :: dparm
  integer         :: iparm
  common    /m2parm/ dparm(30),iparm(30)
  ! 22 Jul 2015: [LY] ensure these params in the right order...
  !              provide these params as arguments instead of reading from file
  integer(ip),  intent(in)  :: nb
  character(8), intent(in)  :: Probname
  integer(ip),  intent(in)  :: m, n, ne
  integer(ip)               :: nnCon, nnJac, neJac
  integer(ip), dimension(ne),  intent(in)  :: ha
  integer(ip), dimension(n+1),  intent(in)  :: ka
  real(dp), dimension(ne), intent(in)    :: ad
  real(dp), dimension(nb), intent(in)    :: bld, bud
  logical, intent(in)       :: warm

  ! Local variables for MINOS
  integer(ip)               :: INFO, iExit
  integer(ip)               :: iSpecs, nnObj
  ! 30 Jul 2015: [LY] want to return inform (exit status) to user
  integer(ip)               :: iObj, iPrint, iSumm, nout
  integer(ip),intent(inout) :: inform
  integer(ip)               :: nInf, nname, nS
  real(dp)                  :: ObjAdd, obj, sInf
  ! LY: allocatable: at run time, allocate() used to assign memory for storage during execution
  !  integer(ip),  allocatable :: hs(:)
  integer(ip),intent(inout) :: hs(nb)
  real(dp)                  :: a(ne)
  ! 22 Jul 2015: [LY] no need to allocate dynamically
  real(dp)                  :: bl(nb), bu(nb)
  real(dp),     allocatable :: cObj(:)
  ! 21 Mar 2016: [LY] return pi (shadow prices) and rc (reduced costs)
  real(dp),     intent(out) :: pi(m)
  real(dp),     intent(out) :: rc(nb)
  real(dp),     intent(out) :: xn(nb)         ! double-rounded version of xn, which is quad

  integer(ip),  allocatable :: name1(:), name2(:)
  character(8)              :: names(5)

  integer(ip)                :: lenz = 100000000 ! As big as you like.
                                                 ! Corrected if inform==42
  integer(ip)               :: nwcore
  integer(ip)               :: mincor

  real(dp), allocatable     :: z(:)           ! This is the MINOS workspace.

  ! Local variables for the problem
  real(dp),     parameter   :: zero = 0.0_dp
  integer(ip)               :: i, l, col, ptr, row

  !------------------------------------------------------------------
  ! Allocate workspace
!   print*, 'Allocating z'
  allocate(z(lenz))


  a  = real(ad, dp)
  bl = real(bld,dp)
  bu = real(bud,dp)


!   print*, 'Allocating name1, name2'
  allocate( name1(nname), name2(nname) )

!   print*, 'No Jacobian matrix since no nonlinear obj or constraints'
  nnCon     = 0
  nnJac     = 0
  nnObj     = 0

  ! Assign various names.
  ! These are relics from the days of MPS files.
  ! They appear in the MINOS Print file and/or Solution file.

  names(1) = Probname
  names(2) = 'c       '  ! Objective name
  names(3) = 'b       '  ! RHS name
  names(4) = '        '  ! Ranges name (bounds on slacks)
  names(5) = 'bounds  '  ! Bounds name (bounds on variables)

  ! Specify file numbers for MINOS.  (Others may be in the SPECS file.)
  ! 0 means that there should be no file.

  !ispecs = 14   ! The MINOS SPECS   file.
  ispecs = 0   ! The MINOS SPECS   file.
! ispecs2= 5   ! The second SPECS  file (for warm start)
  iprint = 9   ! The MINOS PRINT   file.
  isumm  = 6   ! The MINOS SUMMARY file.
  nout   = 6   ! Local output file (6 = screen).

  ! RULE OF THUMB:
  ! MINOS won't open file ispec (for example)
  ! if that unit is already open, or if ispec = 0.
  !------------------------------------------------------------------

  !------------------------------------------------------------------
  ! mistart MUST BE CALLED BEFORE ANY OTHER MINOS ROUTINE.
  !------------------------------------------------------------------
  call mistart( iprint, isumm, ispecs )  ! Initialize MINOS and open
                                         ! the specified files.

  !call mispec( ispecs, inform )          ! Read the SPECS file
                                         ! (if ispecs > 0).

  !----------------------------------------------------------------------
  ! Specify options directly
  ! Options written as one string
  do i=1, nStrOpts
!     write(*,*) 'Calling miopt to set option: ', trim(stropts(i))
    call miopt(trim(stropts(i)), iprint, isumm, inform)
  end do

  ! Integer valued options
  do i=1, nIntOpts
!     write(*,*) 'Calling miopti to set option ', trim(intopts(i)), ' to ', intvals(i)
    call miopti(trim(intopts(i)), intvals(i), iprint, isumm, inform)
  end do

  ! Real-valued options
  do i=1, nRealOpts
!     write(*,*) 'Calling mioptr to set option ', trim(realopts(i)), ' to ', realvals(i)
    call mioptr(trim(realopts(i)), realvals(i), iprint, isumm, inform)
  end do
  !**********************************************************
  ! DEBUG
!   print *, 'Set all options'
  !**********************************************************

  !----------------------------------------------------------------------
  if (inform >= 2) then
     write(nout, *) 'Error: ispecs > 0 but no SPECS file found'
     stop
  end if

  !----------------------------------------------------------------------
  ! Solve the problem.
  ! iobj   = 0    means there is no linear objective row in a(*).
  ! objadd = zero means there is no constant to be added to the objective.
  ! nname  = 1    means there are no meaningful names for the
  !               variables and constraints inside name1(*) and name2(*).
  !               MINOS will print default names.
  !----------------------------------------------------------------------
  xn(1:nb) = zero
  pi(1:m)  = zero
  iObj     = m      ! Always the last row, appended on constraint matrix
  objadd   = zero
  nwcore   = lenz
  nname    = 1
  ObjAdd   = zero

  ! dumpLP.m generates slack bounds for SQOPT: Ax - s = 0
  ! Minos has Ax + s = 0, so we have to flip the bounds on s.

  z(1:m)     = -bl(n+1:nb)
  bl(n+1:nb) = -bu(n+1:nb)
  bu(n+1:nb) =   z(1:m)

  if (warm) then
      print *, 'Calling minoss. Warm start with provided basis (hs)'

      call minoss( 'Warm', m, n, nb, ne, nname,        &
          nncon, nnobj, nnjac,                &
          iobj, objadd, names,                &
          a, ha, ka, bl, bu, name1, name2,    &
          hs, xn, pi, rc,                     &
          inform, mincor, ns, ninf, sinf, obj, &
          z, nwcore )

      if (inform == 42) then
          ! Resize the z (MINOS workspace)
          lenz = mincor
          nwcore = lenz
          write(*,*) 'Reallocating minos workspace to ', lenz
          deallocate(z)
          allocate(z(lenz))

          ! Call minos with now sufficient size z
          call minoss( 'Warm', m, n, nb, ne, nname,        &
              nncon, nnobj, nnjac,                &
              iobj, objadd, names,                &
              a, ha, ka, bl, bu, name1, name2,    &
              hs, xn, pi, rc,                     &
              inform, mincor, ns, ninf, sinf, obj, &
              z, nwcore )
      end if

      write(nout, *) ' '
      write(nout, *) 'MINOS finished.'
      write(nout, *) 'inform =', inform
      write(nout, *) 'ninf   =', ninf
      write(nout, *) 'sinf   =', sinf
      write(nout, *) 'obj    =', obj

  else
      print *, 'Calling minoss. Cold start'

      call minoss( 'Cold', m, n, nb, ne, nname,        &
          nncon, nnobj, nnjac,                &
          iobj, objadd, names,                &
          a, ha, ka, bl, bu, name1, name2,    &
          hs, xn, pi, rc,                     &
          inform, mincor, ns, ninf, sinf, obj, &
          z, nwcore )

      if (inform == 42) then
          ! Resize the z (MINOS workspace)
          lenz = mincor
          nwcore = lenz
          write(*,*) 'Reallocating minos workspace to ', lenz
          deallocate(z)
          allocate(z(lenz))

          ! Call minos with now sufficient size z
          call minoss( 'Cold', m, n, nb, ne, nname,        &
              nncon, nnobj, nnjac,                &
              iobj, objadd, names,                &
              a, ha, ka, bl, bu, name1, name2,    &
              hs, xn, pi, rc,                     &
              inform, mincor, ns, ninf, sinf, obj, &
              z, nwcore )

      end if


      write(nout, *) ' '
      write(nout, *) 'MINOS finished.'
      write(nout, *) 'inform =', inform
      write(nout, *) 'ninf   =', ninf
      write(nout, *) 'sinf   =', sinf
      write(nout, *) 'obj    =', obj

  end if

  900 close( iprint )
  close( ispecs )

  !deallocate( hs, pi, rc, xn )
  !deallocate( xn )
  deallocate( name1, name2 )

contains

end subroutine warmLP

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

subroutine funcon
end subroutine funcon

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

subroutine funobj
end subroutine funobj

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

subroutine matmod
end subroutine matmod

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
