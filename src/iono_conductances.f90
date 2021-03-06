!^CFG COPYRIGHT UM
!*************************************************************************
!
! CONDUCTANCE Calculation Routines
!
!*************************************************************************


!-------------------------------------------------------------------------
! FACs_to_fluxes
!
!
!
!-------------------------------------------------------------------------

subroutine FACs_to_fluxes(iModel, iBlock)

  !\
  ! The goal here is to convert the ionospheric FAC pattern into a 
  ! particle precipitation pattern, which can then be turned into
  ! a conductance pattern.
  !/

  use ModIonosphere
  use IE_ModMain
  use ModNumConst
  use CON_planet_field
  use ModCoordTransform, ONLY: sph_to_xyz

  implicit none

  integer, intent(in) :: iModel  ! model number, 
                                 ! same as conductance_model in IE_ModMain

  integer, intent(in) :: iBlock  ! 1 for northern, 2 for southern hemisphere

  real(real8_)    :: aurora_peak_lat, eflux_peak_lon, ave_e_peak_lon
  real(real8_)    :: aurora_peak_width, ave_e_peak
  real(real8_)    :: distance, mult_fac, ef, efp, mfc
  real(real8_)    :: hal_a0, hal_a1, hal_a2, ped_a0, ped_a1, ped_a2, hall, ped
  real(real8_)    :: dlat, dmlt, y1, y2, x1, x2
  real(real8_)    :: day_colat, dusk_colat, midnight_colat, dawn_colat
  real(real8_)    :: day_fac, dusk_fac, midnight_fac, dawn_fac
  real(real8_)    :: noon_mid, dusk_dawn, oval_shift
  real(real8_)    :: mean_colat, dev_colat, night_width
  real(real8_)    :: PolarCapHallConductance, PolarCap_AveE, PolarCap_EFlux
  integer :: jlat, imlt
  integer :: i,j, n, nloc, nHalfSmooth
  real(real8_), dimension(1:IONO_nPsi) :: Strength_of_Oval,               &
       Loc_of_Oval, Width_of_Oval
  logical :: polarcap, IsPeakFound, IsDone
  real(real8_) :: Center, Width, Beta
  real(real8_) :: f, MaxP, MaxT, MulFac_ae, MulFac_ef, MinWidth, ThetaOCB, AuroraWidth
  real(real8_) :: MulFac_Dae, MulFac_Def, bIono, Rm, Te, eV, bIono_D(3), XyzIono_D(3)
  real(real8_), dimension(IONO_nTheta,IONO_nPsi) :: nDen, &
       discrete_k, discrete_ae, discrete_ef, diffuse_ae, diffuse_ef,F0
  real(real8_), dimension(IONO_nPsi) :: OCFLB, EquatorwardEdge, Smooth
  real(real8_), parameter:: e_mass = 9.1e-31
  !---------------------------------------------------------------------------
  Hall_to_Ped_Ratio = 1.5

  if (PolarCapPedConductance > 0.0) then
     PolarCapHallConductance = Hall_to_Ped_Ratio * PolarCapPedConductance
     PolarCap_AveE = (Hall_to_Ped_Ratio/0.45)**(1.0/0.85)
     PolarCap_EFlux = ((PolarCapPedConductance*(16.0 + PolarCap_AveE**2) / &
          (40.0*PolarCap_AveE))**2)/1000.0 ! convert ergs/cm2/s to W/m2
  else
     PolarCap_AveE  = IONO_Min_Ave_E
     PolarCap_EFlux = IONO_Min_EFlux
  endif

  if (iModel.eq.7) then

     
     MulFac_Dae = 1.0e22
     MulFac_Def = 1.0e19
     MulFac_ef = 0.3e6
     MulFac_ae = 4.0e-12

     !Yu: recalculate the coefficients (by comparing to J. Raeder's formulas. take F1=4)
     MulFac_Dae = 0.0267
     MulFac_Def = 6.0e17

     if (iBlock==1)then

        !\
        ! pass the diffuse energy from IM integrated over the loss cone due to WPI
        !/

        iono_north_eflux = iono_north_im_eflux/1000.0 !from ergs/cm^2s to W/m^2
        iono_north_ave_e = iono_north_im_avee ! keV

        where (iono_north_ave_e > 20.0) &
             iono_north_ave_e = 20.0

        ! add the polar cap region and gradual decay from aurora        
        ! if stand alone, do not need this
!        do j = 1, IONO_nPsi
!           i = 1
!           do while (iono_north_eflux(i,j) == 0.0 .and. i < Iono_nTheta)
!              i = i + 1
!           enddo
!           if (i > 2) iono_north_eflux(i-1,j) = iono_north_eflux(i,j)* 0.66 
!           if (i > 3) iono_north_eflux(i-2,j) = iono_north_eflux(i,j)* 0.33
!           if (i > 4) iono_north_eflux(1:i-3,j) = PolarCap_EFlux
!           if (i > 2) iono_north_ave_e(i-1,j) = iono_north_ave_e(i,j)
!           if (i > 3) iono_north_ave_e(i-2,j) = iono_north_ave_e(i,j)
!           if (i > 4) iono_north_ave_e(1:i-3,j) = PolarCap_AveE
!        enddo
        
        where (iono_north_eflux < IONO_Min_EFlux) &
             iono_north_eflux = IONO_Min_EFlux

        diffuse_ef = iono_north_eflux
        diffuse_ae = iono_north_ave_e
         
        !\
        ! pass the discrete energy from IM using Te, Ne from RAM, following Zhang et al.2015 formulas
        !/
        ! it is only applied in Jr>0 region
        iono_north_eflux = iono_north_im_dis_eflux/1000.0
        iono_north_ave_e = iono_north_im_dis_avee

        where (iono_north_ave_e > 20.0) &
             iono_north_ave_e = 20.0
        where (iono_north_eflux < IONO_Min_EFlux) &
             iono_north_eflux = IONO_Min_EFlux

        discrete_ef = iono_north_eflux
        discrete_ae = iono_north_ave_e


        ! Below follows Zhang etal.2015
        
!        discrete_ef = 0.0
!        discrete_k  = 0.0
!
!        F0 = Beta * sqrt(iono_north_rho*iono_north_p/(2*cPi*cElectronMass*cProtonMass*6.0))        
!
!        do j = 1, IONO_nPsi
!           do i = 1, IONO_nTheta
!              call sph_to_xyz(Radius, IONO_NORTH_Theta(i,j), IONO_NORTH_Psi(i,j), XyzIono_D)
!              call get_planet_field(Time_Simulation, XyzIono_D, 'SMG', bIono_D)
!              bIono = sqrt(sum(bIono_D**2))
!              Rm = bIono/iono_north_beq(i,j)
!              if (j .eq. 100 .and.i.eq.30)write(*,*)'bIono, Beq:', bIono, iono_north_beq(i,j)
!
!              Te = iono_north_p(i,j)/(iono_north_rho(i,j)+1.0e-32)*cProtonMass /6.0
!
!              if (iono_north_jr(i,j) .gt. 0.0 .and. F0(i,j) .gt. 0.0)then
!                 eV = Te*(Rm-1)*log( (Rm-1)/(Rm-iono_north_jr(i,j)/1.6e-19/F0(i,j)))
!                 
!                 discrete_ef(i,j) = iono_north_jr(i,j)/1.6e-19* &
!                      (2*Te + eV*(1-exp(-1*eV/Te/(Rm-1)))/(1+(1-1/Rm)*exp(-1*eV/Te/(Rm-1))))
!
!                 discrete_ae(i,j) = discrete_ef(i,j)/(iono_north_jr(i,j)/1.6e-19)/1.6e-16 ! keV
!
!                 if(j.eq. 100.and.i.eq.30)write(*,*)'Te,eV,discrete_ef:',Te,eV,discrete_ef(i,j)
!                 if(j.eq. 100.and.i.eq.30)write(*,*)'Rm,jr,F0:',Rm,iono_north_jr(i,j),F0(i,j),Rm-1,&
!                      Rm-iono_north_jr(i,j)/1.6e-19/F0(i,j),log(Rm-1),log(Rm-iono_north_jr(i,j)/1.6e-19/F0(i,j)),log(10.0)
!              endif
!
!           enddo
!        enddo
!
! ----------------------------------------------------------------------
        ! another way following Raeder 2001,1999 
! ----------------------------------------------------------------------
!
!        ! This is from Jimmy's Paper on the Knight Relationship
!        where (iono_north_p > 0) discrete_k = &
!             (iono_north_rho**1.5) / sqrt(iono_north_p/6.0)
!        ! Mirror the particles, since we are dealing with electrons and not
!        ! ions.
!        do j = 1, IONO_nPsi
!           discrete_k(:,j) = discrete_k(:,IONO_nPsi-j+1)
!        enddo
!        where (iono_north_jr > 0.0) &
!             discrete_ef = iono_north_jr*discrete_k
!        discrete_ae = discrete_ef*MulFac_Dae/1.6e-16 ! to keV
!        discrete_ef = iono_north_jr*discrete_ef*MulFac_Def
        

        ! Let's add a little conductance on ANY not in the polar cap,
        ! so the code doesn't blow up
!        do j = 1, IONO_nPsi
!           do i = 1, IONO_nTheta
!              if (abs(iono_north_jr(i,j)) > 0.0 .and. &
!                   discrete_ef(i,j) < 5.0e-3) then
!                 discrete_ef(i,j) = MulFac_Def/2.5 * &
!                      (iono_north_jr(i,j))**2*discrete_k(i,j)
!              endif
!           enddo
!        enddo
!        
        where (diffuse_ae < IONO_Min_Ave_E/2) diffuse_ae = IONO_Min_Ave_E/2
        where (discrete_ae < IONO_Min_Ave_E/2) discrete_ae = IONO_Min_Ave_E/2

        write(*,*)'max discrete/diffuse',maxval(discrete_ef),maxval(diffuse_ef)
        write(*,*)'max discrete/diffuse ave_e:',maxval(discrete_ae),maxval(diffuse_ae)
        write(*,*)'max rho,p,jr: ',maxval(iono_north_rho),maxval(iono_north_p),maxval(iono_north_jr)

        
        ! Let's weight the average energy by the number flux, which is ef/av
        iono_north_ave_e = &
             (diffuse_ef + discrete_ef) / &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae)
        
        ! The energy flux should be weighted by the average energy
        iono_north_eflux = &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae) * &
             iono_north_ave_e
        
        where (iono_north_ave_e < IONO_Min_Ave_E) &
             iono_north_ave_e = IONO_Min_Ave_E
     
     else

        iono_south_eflux = iono_south_im_eflux/1000.0
        iono_south_ave_e = iono_south_im_avee

        where (iono_south_ave_e > 20.0) &
             iono_south_ave_e = 20.0

        ! add the polar cap region and gradual decay from aurora
!        do j = 1, IONO_nPsi
!           i = 1
!           do while (iono_south_eflux(i,j) == 0.0 .and. i < Iono_nTheta)
!              i = i + 1
!           enddo
!           if (i > 2) iono_south_eflux(i-1,j) = iono_south_eflux(i,j)* 0.66 
!           if (i > 3) iono_south_eflux(i-2,j) = iono_south_eflux(i,j)* 0.33
!           if (i > 4) iono_south_eflux(1:i-3,j) = PolarCap_EFlux
!           if (i > 2) iono_south_ave_e(i-1,j) = iono_south_ave_e(i,j)
!           if (i > 3) iono_south_ave_e(i-2,j) = iono_south_ave_e(i,j)
!           if (i > 4) iono_south_ave_e(1:i-3,j) = PolarCap_AveE
!        enddo
        
        where (iono_south_eflux < IONO_Min_EFlux) &
             iono_south_eflux = IONO_Min_EFlux

        diffuse_ef = iono_south_eflux
        diffuse_ae = iono_south_ave_e

        !\
        ! pass the discrete energy from IM using Te, Ne from RAM, following Zhang et al.2015 formulas
        !/
        ! it is only applied in Jr>0 region
        iono_south_eflux = iono_south_im_dis_eflux/1000.0
        iono_south_ave_e = iono_south_im_dis_avee

        where (iono_south_ave_e > 20.0) &
             iono_south_ave_e = 20.0
        where (iono_south_eflux < IONO_Min_EFlux) &
             iono_south_eflux = IONO_Min_EFlux
        
        discrete_ef =  iono_south_eflux
        discrete_ae =  iono_south_ave_e

        

!        discrete_ef = 0.0
!        discrete_k  = 0.0
!        F0 = Beta * sqrt(iono_south_rho*iono_south_p/(2*cPi*cElectronMass*cProtonMass*6.0))
!        do j = 1, IONO_nPsi
!           do i = 1, IONO_nTheta
!              call sph_to_xyz(Radius, IONO_SOUTH_Theta(i,j), IONO_SOUTH_Psi(i,j), XyzIono_D)
!              call get_planet_field(Time_Simulation, XyzIono_D, 'SMG', bIono_D)
!              bIono = sqrt(sum(bIono_D**2))
!              Rm = bIono/iono_south_beq(i,j)
!
!              Te = iono_south_p(i,j)/(iono_south_rho(i,j)+1.0e-32)*cProtonMass /6.0
!
!              ! F0 is zero in the cap region, cannot be divided by zero.
!              if (iono_south_jr(i,j) .gt. 0.0 .and. F0(i,j) .gt. 0.0)then
!                 eV = Te*(Rm-1)*log( (Rm-1)/(Rm-iono_south_jr(i,j)/1.6e-19/F0(i,j)))
!
!                 discrete_ef(i,j) = iono_south_jr(i,j)/1.6e-19* &
!                      (2*Te + eV*(1-exp(-1*eV/Te/(Rm-1)))/(1+(1-1/Rm)*exp(-1*eV/Te/(Rm-1))))
!
!                 discrete_ae(i,j) = discrete_ef(i,j)/(iono_south_jr(i,j)/1.6e-19)/1.6e-16 !keV
!
!              endif
!
!           enddo
!        enddo

!----------------------------------------------------------------
!        ! This is from Jimmy's Paper on the Knight Relationship
!        where (iono_south_p > 0) discrete_k = &
!             (iono_south_rho**1.5) / sqrt(iono_south_p/6.0)
!        ! Reverse the particles again.
!        do j = 1, IONO_nPsi
!           discrete_k(:,j) = discrete_k(:,IONO_nPsi-j+1)
!        enddo
!
!        where (iono_south_jr > 0.5e-7) &
!             discrete_ef = iono_south_jr*discrete_k
!        discrete_ae = discrete_ef*MulFac_Dae/1.0e-16 ! J to keV
!        discrete_ef = iono_south_jr*discrete_ef*MulFac_Def
!
!
!        ! Let's add a little conductance on ANY not in the polar cap,
!        ! so the code doesn't blow up
!        do j = 1, IONO_nPsi
!           do i = 1, IONO_nTheta
!              if (abs(iono_south_jr(i,j)) > 0.0 .and. &
!                   discrete_ef(i,j) < 5.0e-3) then
!                 discrete_ef(i,j) = MulFac_Def/2.5 * &
!                      (iono_south_jr(i,j))**2*discrete_k(i,j)
!              endif
!           enddo
!        enddo
!
        where (diffuse_ae < IONO_Min_Ave_E/2) diffuse_ae = IONO_Min_Ave_E/2
        where (discrete_ae < IONO_Min_Ave_E/2) discrete_ae = IONO_Min_Ave_E/2

        ! Let's weight the average energy by the number flux, which is ef/av
        iono_south_ave_e = &
             (diffuse_ef + discrete_ef) / &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae)

        ! The energy flux should be weighted by the average energy
        iono_south_eflux = &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae) * &
             iono_south_ave_e

        where (iono_south_ave_e < IONO_Min_Ave_E) &
             iono_south_ave_e = IONO_Min_Ave_E

     endif

  end if


  if (iModel.eq.3) then

     mult_fac   = 0.25*0.33e7*2.0e-3
     ave_e_peak = max(3.0, PolarCap_AveE)                        ! keV

     oval_shift = 10.0*cDegToRad

     select case(iBlock)
     case(1)
        !\
        ! Do North first -----------------------------------------------------
        !/

        call Determine_Oval_Characteristics(IONO_NORTH_JR, &
             IONO_NORTH_Theta, &
             IONO_NORTH_Psi, &
             Loc_of_Oval, &
             Width_of_Oval, &
             Strength_of_Oval)

        ave_e_peak_lon = 0.0

        do i = 1, IONO_nTheta
           do j = 1, IONO_nPsi

              ! Energy Flux

              distance = IONO_NORTH_Theta(i,j)-(Loc_of_Oval(j)+oval_shift)
              IONO_NORTH_EFlux(i,j) =                                       &
                   Strength_of_Oval(j) * &
                   mult_fac * &
                   exp(-1.0*(distance/Width_of_Oval(j))**2)

              if (distance < 0.0) then
                 IONO_NORTH_EFlux(i,j) = &
                      max(IONO_NORTH_EFlux(i,j), PolarCap_EFlux)
                 polarcap = .true.
              else
                 IONO_NORTH_EFlux(i,j) = &
                      max(IONO_NORTH_EFlux(i,j), IONO_Min_EFlux)
                 polarcap = .false.
              endif

              ! Average Energy
              IONO_NORTH_Ave_E(i,j) =                                      &
                   ave_e_peak*exp(-1.0*(distance/Width_of_Oval(j))**2)

              if (PolarCap_AveE == IONO_Min_Ave_E) then
                 distance = 0.25 +                                          &
                      0.75*(                                                &
                      sin(IONO_NORTH_Psi(i,j)-(ave_e_peak_lon + cHalfPi)) &
                      + 1.0)/2.0
              else
                 distance = 1.0
              endif

              IONO_NORTH_Ave_E(i,j) = IONO_NORTH_Ave_E(i,j)*distance

              if (polarcap) then
                 IONO_NORTH_Ave_E(i,j) = &
                      max(IONO_NORTH_Ave_E(i,j), PolarCap_AveE)
              else
                 IONO_NORTH_Ave_E(i,j) = &
                      max(IONO_NORTH_Ave_E(i,j), IONO_Min_Ave_E)
              endif

           enddo
        enddo

     case(2)
        !\
        ! Do South next --------------------------------------------------------
        !/

        call Determine_Oval_Characteristics(IONO_SOUTH_JR, &
             IONO_SOUTH_Theta, &
             IONO_SOUTH_Psi, &
             Loc_of_Oval, &
             Width_of_Oval, &
             Strength_of_Oval)

        Loc_of_Oval = cPi - Loc_of_Oval

        ave_e_peak_lon = 0.0

        do i = 1, IONO_nTheta
           do j = 1, IONO_nPsi

              ! Energy Flux

              distance = IONO_SOUTH_Theta(i,j)-(Loc_of_Oval(j)-oval_shift)
              IONO_SOUTH_EFlux(i,j) =                                            &
                   Strength_of_Oval(j) * &
                   mult_fac * &
                   exp(-1.0*(distance/Width_of_Oval(j))**2)

              if (distance > 0.0) then
                 IONO_SOUTH_EFlux(i,j) = &
                      max(IONO_SOUTH_EFlux(i,j), PolarCap_EFlux)
                 polarcap = .true.
              else
                 IONO_SOUTH_EFlux(i,j) = &
                      max(IONO_SOUTH_EFlux(i,j), IONO_Min_EFlux)
                 polarcap = .false.
              endif

              ! Average Energy

              IONO_SOUTH_Ave_E(i,j) =                                      &
                   ave_e_peak*exp(-1.0*(distance/Width_of_Oval(j))**2)

              if (PolarCap_AveE == IONO_Min_Ave_E) then
                 distance = 0.25 +                                          &
                      0.75*(                                                &
                      sin(IONO_SOUTH_Psi(i,j)-(ave_e_peak_lon + cHalfPi))   &
                      + 1.0)/2.0
              else
                 distance = 1.0
              endif

              IONO_SOUTH_Ave_E(i,j) = IONO_SOUTH_Ave_E(i,j)*distance

              if (polarcap) then
                 IONO_SOUTH_Ave_E(i,j) = &
                      max(IONO_SOUTH_Ave_E(i,j), PolarCap_AveE)
              else
                 IONO_SOUTH_Ave_E(i,j) = &
                      max(IONO_SOUTH_Ave_E(i,j), IONO_Min_Ave_E)
              endif
           enddo
        enddo
     end select
  endif

  if (iModel.eq.4 .or. iModel.eq.5) then

     i_cond_nlats = 16
     i_cond_nmlts = 24

     do j = 1, i_cond_nlats

        hal_a0_up(i_cond_nmlts+1,j) = hal_a0_up(1,j)
        ped_a0_up(i_cond_nmlts+1,j) = ped_a0_up(1,j)
        hal_a0_do(i_cond_nmlts+1,j) = hal_a0_do(1,j)
        ped_a0_do(i_cond_nmlts+1,j) = ped_a0_do(1,j)
        hal_a1_up(i_cond_nmlts+1,j) = hal_a1_up(1,j)
        ped_a1_up(i_cond_nmlts+1,j) = ped_a1_up(1,j)
        hal_a1_do(i_cond_nmlts+1,j) = hal_a1_do(1,j)
        ped_a1_do(i_cond_nmlts+1,j) = ped_a1_do(1,j)
        hal_a2_up(i_cond_nmlts+1,j) = hal_a2_up(1,j)
        ped_a2_up(i_cond_nmlts+1,j) = ped_a2_up(1,j)
        hal_a2_do(i_cond_nmlts+1,j) = hal_a2_do(1,j)
        ped_a2_do(i_cond_nmlts+1,j) = ped_a2_do(1,j)

     enddo

     dlat = (cond_lats(1) - cond_lats(2))*cDegToRad
     dmlt = (cond_mlts(2) - cond_mlts(1))*cPi/12.0

     select case(iBlock)
     case(1)
        !  Do North First

        call Determine_Oval_Characteristics(IONO_NORTH_JR, &
             IONO_NORTH_Theta, &
             IONO_NORTH_Psi, &
             Loc_of_Oval, &
             Width_of_Oval, &
             Strength_of_Oval)

        do j = 1, IONO_nPsi
           do i = 1, IONO_nTheta

              y1 = IONO_NORTH_Theta(i,j)/dlat + 1.0
              if (y1 > i_cond_nlats-1) then
                 jlat = i_cond_nlats-1
                 y1   = 1.0
              else
                 jlat = y1
                 y1   = 1.0 - (y1 - jlat)
              endif
              y2 = 1.0 - y1

              x1 = mod((IONO_NORTH_Psi(i,j) + cPi), cTwoPi)/dmlt + 1.0
              imlt = x1
              x1   = 1.0 - (x1 - imlt)
              x2   = 1.0 - x1

              if (iono_north_jr(i,j) > 0) then

                 hal_a0 = x1*y1*hal_a0_up(imlt  ,jlat  ) + &
                      x2*y1*hal_a0_up(imlt+1,jlat  ) + &
                      x1*y2*hal_a0_up(imlt  ,jlat+1) + &
                      x2*y2*hal_a0_up(imlt+1,jlat+1)

                 hal_a1 = x1*y1*hal_a1_up(imlt  ,jlat  ) + &
                      x2*y1*hal_a1_up(imlt+1,jlat  ) + &
                      x1*y2*hal_a1_up(imlt  ,jlat+1) + &
                      x2*y2*hal_a1_up(imlt+1,jlat+1)

                 hal_a2 = x1*y1*hal_a2_up(imlt  ,jlat  ) + &
                      x2*y1*hal_a2_up(imlt+1,jlat  ) + &
                      x1*y2*hal_a2_up(imlt  ,jlat+1) + &
                      x2*y2*hal_a2_up(imlt+1,jlat+1)

                 ped_a0 = x1*y1*ped_a0_up(imlt  ,jlat  ) + &
                      x2*y1*ped_a0_up(imlt+1,jlat  ) + &
                      x1*y2*ped_a0_up(imlt  ,jlat+1) + &
                      x2*y2*ped_a0_up(imlt+1,jlat+1)

                 ped_a1 = x1*y1*ped_a1_up(imlt  ,jlat  ) + &
                      x2*y1*ped_a1_up(imlt+1,jlat  ) + &
                      x1*y2*ped_a1_up(imlt  ,jlat+1) + &
                      x2*y2*ped_a1_up(imlt+1,jlat+1)

                 ped_a2 = x1*y1*ped_a2_up(imlt  ,jlat  ) + &
                      x2*y1*ped_a2_up(imlt+1,jlat  ) + &
                      x1*y2*ped_a2_up(imlt  ,jlat+1) + &
                      x2*y2*ped_a2_up(imlt+1,jlat+1)

              else

                 hal_a0 = x1*y1*hal_a0_do(imlt  ,jlat  ) + &
                      x2*y1*hal_a0_do(imlt+1,jlat  ) + &
                      x1*y2*hal_a0_do(imlt  ,jlat+1) + &
                      x2*y2*hal_a0_do(imlt+1,jlat+1)

                 hal_a1 = x1*y1*hal_a1_do(imlt  ,jlat  ) + &
                      x2*y1*hal_a1_do(imlt+1,jlat  ) + &
                      x1*y2*hal_a1_do(imlt  ,jlat+1) + &
                      x2*y2*hal_a1_do(imlt+1,jlat+1)

                 hal_a2 = x1*y1*hal_a2_do(imlt  ,jlat  ) + &
                      x2*y1*hal_a2_do(imlt+1,jlat  ) + &
                      x1*y2*hal_a2_do(imlt  ,jlat+1) + &
                      x2*y2*hal_a2_do(imlt+1,jlat+1)

                 ped_a0 = x1*y1*ped_a0_do(imlt  ,jlat  ) + &
                      x2*y1*ped_a0_do(imlt+1,jlat  ) + &
                      x1*y2*ped_a0_do(imlt  ,jlat+1) + &
                      x2*y2*ped_a0_do(imlt+1,jlat+1)

                 ped_a1 = x1*y1*ped_a1_do(imlt  ,jlat  ) + &
                      x2*y1*ped_a1_do(imlt+1,jlat  ) + &
                      x1*y2*ped_a1_do(imlt  ,jlat+1) + &
                      x2*y2*ped_a1_do(imlt+1,jlat+1)

                 ped_a2 = x1*y1*ped_a2_do(imlt  ,jlat  ) + &
                      x2*y1*ped_a2_do(imlt+1,jlat  ) + &
                      x1*y2*ped_a2_do(imlt  ,jlat+1) + &
                      x2*y2*ped_a2_do(imlt+1,jlat+1)

              endif

              distance = (IONO_NORTH_Theta(i,j) - Loc_of_Oval(j))

              if (distance > 0.0) then
                 polarcap = .false.
              else
                 polarcap = .true.
              endif

              if (iModel.eq.4) then
                 ! Implemented Feb. 7, 2007 as modified version of iModel 5 with
                 !    new narrower fitting of the auroral oval.  DDZ

                 hall=exp(-1.0*(distance/(OvalWidthFactor*Width_of_Oval(j)))**2) * &
                      OvalStrengthFactor*( &
                      hal_a0+(hal_a1-hal_a0)*exp(-abs(iono_north_jr(i,j)*1.0e9)*hal_a2**2))
                 ped =exp(-1.0*(distance/(OvalWidthFactor*Width_of_Oval(j)))**2) * &
                      OvalStrengthFactor*( &
                      ped_a0+(ped_a1-ped_a0)*exp(-abs(iono_north_jr(i,j)*1.0e9)*ped_a2**2))
              else  ! iModel=5
                 !
                 ! We want minimal conductance lower than the oval
                 !

                 if (.not.polarcap) then
                    distance = distance/3.0
                    hal_a0 = hal_a0 * exp(-1.0*(distance/(Width_of_Oval(j)))**2)
                    ped_a0 = ped_a0 * exp(-1.0*(distance/(Width_of_Oval(j)))**2)
                 end if

                 !
                 ! A sort of correction on the fit
                 !

                 hal_a1 = hal_a0 + (hal_a1 - hal_a0)*  &
                      exp(-1.0*(distance/Width_of_Oval(j))**2)
                 ped_a1 = ped_a0 + (ped_a1 - ped_a0)*  &
                      exp(-1.0*(distance/Width_of_Oval(j))**2)

                 ! Multiply by sqrt(3) to compensate for the 3 times narrower oval
                 hall=1.7*( &
                      hal_a0-hal_a1*exp(-abs(iono_north_jr(i,j)*1.0e9)*hal_a2**2))
                 ped =1.7*( &
                      ped_a0-ped_a1*exp(-abs(iono_north_jr(i,j)*1.0e9)*ped_a2**2))
              end if

              if ((hall.gt.1.0).and.(ped.gt.0.5)) then
                 IONO_NORTH_Ave_E(i,j)  = ((hall/ped)/0.45)**(1.0/0.85)
                 IONO_NORTH_EFlux(i,j) = (ped*(16.0+IONO_NORTH_Ave_E(i,j)**2)/&
                      (40.0*IONO_NORTH_Ave_E(i,j)))**2/1000.0
              else
                 IONO_NORTH_Ave_E(i,j) = IONO_Min_Ave_E
                 IONO_NORTH_EFlux(i,j) = IONO_Min_EFlux
              endif

              if ((PolarCap_AveE > 0.0).and.(polarcap)) then
                 IONO_NORTH_Ave_E(i,j) = max(IONO_NORTH_Ave_E(i,j), &
                      PolarCap_AveE)
                 IONO_NORTH_EFlux(i,j) = max(IONO_NORTH_EFlux(i,j), &
                      PolarCap_EFlux)
              endif

           enddo
        enddo

     case(2)
        !  Do South Next

        call Determine_Oval_Characteristics(IONO_SOUTH_JR, &
             IONO_SOUTH_Theta, &
             IONO_SOUTH_Psi, &
             Loc_of_Oval, &
             Width_of_Oval, &
             Strength_of_Oval)

        Loc_of_Oval = cPI - Loc_of_Oval

        do j = 1, IONO_nPsi
           do i = 1, IONO_nTheta


              y1 = (cPi - IONO_SOUTH_Theta(i,j))/dlat + 1.0
              if (y1 > i_cond_nlats-1) then
                 jlat = i_cond_nlats-1
                 y1   = 1.0
              else
                 jlat = y1
                 y1   = 1.0 - (y1 - jlat)
              endif
              y2 = 1.0 - y1

              x1 = mod((IONO_SOUTH_Psi(i,j) + cPi), cTwoPi)/dmlt + 1.0
              imlt = x1
              x1   = 1.0 - (x1 - imlt)
              x2   = 1.0 - x1

              if (iono_south_jr(i,j) > 0) then

                 hal_a0 = x1*y1*hal_a0_up(imlt  ,jlat  ) + &
                      x2*y1*hal_a0_up(imlt+1,jlat  ) + &
                      x1*y2*hal_a0_up(imlt  ,jlat+1) + &
                      x2*y2*hal_a0_up(imlt+1,jlat+1)

                 hal_a1 = x1*y1*hal_a1_up(imlt  ,jlat  ) + &
                      x2*y1*hal_a1_up(imlt+1,jlat  ) + &
                      x1*y2*hal_a1_up(imlt  ,jlat+1) + &
                      x2*y2*hal_a1_up(imlt+1,jlat+1)

                 hal_a2 = x1*y1*hal_a2_up(imlt  ,jlat  ) + &
                      x2*y1*hal_a2_up(imlt+1,jlat  ) + &
                      x1*y2*hal_a2_up(imlt  ,jlat+1) + &
                      x2*y2*hal_a2_up(imlt+1,jlat+1)

                 ped_a0 = x1*y1*ped_a0_up(imlt  ,jlat  ) + &
                      x2*y1*ped_a0_up(imlt+1,jlat  ) + &
                      x1*y2*ped_a0_up(imlt  ,jlat+1) + &
                      x2*y2*ped_a0_up(imlt+1,jlat+1)

                 ped_a1 = x1*y1*ped_a1_up(imlt  ,jlat  ) + &
                      x2*y1*ped_a1_up(imlt+1,jlat  ) + &
                      x1*y2*ped_a1_up(imlt  ,jlat+1) + &
                      x2*y2*ped_a1_up(imlt+1,jlat+1)

                 ped_a2 = x1*y1*ped_a2_up(imlt  ,jlat  ) + &
                      x2*y1*ped_a2_up(imlt+1,jlat  ) + &
                      x1*y2*ped_a2_up(imlt  ,jlat+1) + &
                      x2*y2*ped_a2_up(imlt+1,jlat+1)

              else

                 hal_a0 = x1*y1*hal_a0_do(imlt  ,jlat  ) + &
                      x2*y1*hal_a0_do(imlt+1,jlat  ) + &
                      x1*y2*hal_a0_do(imlt  ,jlat+1) + &
                      x2*y2*hal_a0_do(imlt+1,jlat+1)

                 hal_a1 = x1*y1*hal_a1_do(imlt  ,jlat  ) + &
                      x2*y1*hal_a1_do(imlt+1,jlat  ) + &
                      x1*y2*hal_a1_do(imlt  ,jlat+1) + &
                      x2*y2*hal_a1_do(imlt+1,jlat+1)

                 hal_a2 = x1*y1*hal_a2_do(imlt  ,jlat  ) + &
                      x2*y1*hal_a2_do(imlt+1,jlat  ) + &
                      x1*y2*hal_a2_do(imlt  ,jlat+1) + &
                      x2*y2*hal_a2_do(imlt+1,jlat+1)

                 ped_a0 = x1*y1*ped_a0_do(imlt  ,jlat  ) + &
                      x2*y1*ped_a0_do(imlt+1,jlat  ) + &
                      x1*y2*ped_a0_do(imlt  ,jlat+1) + &
                      x2*y2*ped_a0_do(imlt+1,jlat+1)

                 ped_a1 = x1*y1*ped_a1_do(imlt  ,jlat  ) + &
                      x2*y1*ped_a1_do(imlt+1,jlat  ) + &
                      x1*y2*ped_a1_do(imlt  ,jlat+1) + &
                      x2*y2*ped_a1_do(imlt+1,jlat+1)

                 ped_a2 = x1*y1*ped_a2_do(imlt  ,jlat  ) + &
                      x2*y1*ped_a2_do(imlt+1,jlat  ) + &
                      x1*y2*ped_a2_do(imlt  ,jlat+1) + &
                      x2*y2*ped_a2_do(imlt+1,jlat+1)

              endif

              distance = (IONO_SOUTH_Theta(i,j)-Loc_of_Oval(j))

              if (distance < 0.0) then
                 polarcap = .false.
              else
                 polarcap = .true.
              endif

              if (iModel.eq.4) then
                 hall=exp(-1.0*(distance/(OvalWidthFactor*Width_of_Oval(j)))**2) * &
                      OvalStrengthFactor*( &
                      hal_a0+(hal_a1-hal_a0)*exp(-abs(iono_north_jr(i,j)*1.0e9)*hal_a2**2))
                 ped =exp(-1.0*(distance/(OvalWidthFactor*Width_of_Oval(j)))**2) * &
                      OvalStrengthFactor*( &
                      ped_a0+(ped_a1-ped_a0)*exp(-abs(iono_north_jr(i,j)*1.0e9)*ped_a2**2))
              else  ! iModel=5
                 if (.not.polarcap) then
                    distance = distance/3.0
                    hal_a0 = hal_a0 * exp(-1.0*(distance/(Width_of_Oval(j)))**2)
                    ped_a0 = ped_a0 * exp(-1.0*(distance/(Width_of_Oval(j)))**2)
                 endif

                 !
                 ! A sort of correction on the fit
                 !

                 hal_a1 = hal_a0 + (hal_a1 - hal_a0)*  &
                      exp(-1.0*(distance/Width_of_Oval(j))**2)
                 ped_a1 = ped_a0 + (ped_a1 - ped_a0)*  &
                      exp(-1.0*(distance/Width_of_Oval(j))**2)

                 ! Multiply by sqrt(3) to compensate for the 3 times narrower oval
                 hall=1.7*( &
                      hal_a0-hal_a1*exp(-abs(iono_south_jr(i,j)*1.0e9)*hal_a2**2))
                 ped =1.7*( &
                      ped_a0-ped_a1*exp(-abs(iono_south_jr(i,j)*1.0e9)*ped_a2**2))
              end if

              if ((hall.gt.1.0).and.(ped.gt.0.5)) then
                 IONO_SOUTH_Ave_E(i,j)  = ((hall/ped)/0.45)**(1.0/0.85)
                 IONO_SOUTH_EFlux(i,j) = (ped*(16.0+IONO_SOUTH_Ave_E(i,j)**2)/&
                      (40.0*IONO_SOUTH_Ave_E(i,j)))**2/1000.0
              else
                 IONO_SOUTH_Ave_E(i,j) = IONO_Min_Ave_E
                 IONO_SOUTH_EFlux(i,j) = IONO_Min_EFlux
              endif

              if ((PolarCap_AveE > 0.0).and.(polarcap)) then
                 IONO_SOUTH_Ave_E(i,j) = max(IONO_SOUTH_Ave_E(i,j), &
                      PolarCap_AveE)
                 IONO_SOUTH_EFlux(i,j) = max(IONO_SOUTH_EFlux(i,j),        &
                      PolarCap_EFlux)
              endif

           enddo
        enddo
     end select
  end if

  if (iModel.eq.6) then

     MinWidth = 5.0 * cPi / 180.0
     nHalfSmooth = 5
!     MulFac_Dae = 1.0e22
!     MulFac_Def = 5.0e19
!     MulFac_ef = 0.2e7
!     MulFac_ae = 1.0 / 1.0e11
     MulFac_Dae = 1.0e22
     MulFac_Def = 1.0e19
     MulFac_ef = 0.3e6
     MulFac_ae = 4.0e-12

     !Yu: recalculate the coefficients (by comparing to J. Raeder's formulas. take F1=4)
     MulFac_Dae = 0.0267
     MulFac_Def = 6.0e17

     if (iBlock == 1) then 

        iono_north_eflux = 1.0e-6
        iono_north_ave_e = 1.0

        OCFLB = -1.0
        EquatorWardEdge = -1.0

        do j = 1, IONO_nPsi
           IsPeakFound = .false.
           MaxP = max(maxval(iono_north_p(:,IONO_nPsi-j+1)),1.0e-15)
           IsDone = .false.
           i = 1
           do while (.not. IsDone)

              if (iono_north_p(i,IONO_nPsi-j+1) > 0) then

                 if (OCFLB(j) == -1) OCFLB(j) = iono_north_theta(i,j)
                 AuroraWidth = iono_north_theta(i,j) - OCFLB(j)
                 iono_north_eflux(i,j) = MulFac_ef*MaxP

                 if (iono_north_p(i,IONO_nPsi-j+1)==MaxP) IsPeakFound = .true.

                 if (IsPeakFound .and. AuroraWidth >= MinWidth) then
                    EquatorWardEdge(j) = iono_north_theta(i,j)
                    IsDone = .true.
                 endif

              endif

              if (i == IONO_nTheta) IsDone = .true.
              i = i + 1

           enddo
           if (.not. IsPeakFound) then
              OCFLB(j) = MinWidth
              EquatorwardEdge(j) = MinWidth*2
           endif

        enddo

        do j = 1, IONO_nPsi
           smooth(j) = 0.0
           do i = j-nHalfSmooth-1, j+nHalfSmooth-1
              smooth(j) = smooth(j) + OCFLB(mod(i+IONO_nPsi,IONO_nPsi)+1)
           enddo
        enddo
        OCFLB = smooth/(nHalfSmooth*2+1)
           
        do j = 1, IONO_nPsi
           smooth(j) = 0.0
           do i = j-nHalfSmooth-1, j+nHalfSmooth-1
              smooth(j) = smooth(j) + &
                   EquatorWardEdge(mod(i+IONO_nPsi,IONO_nPsi)+1)
           enddo
        enddo
        EquatorWardEdge = smooth/(nHalfSmooth*2+1)

        do j = 1, IONO_nPsi

           Center = (OCFLB(j)*2.0 + EquatorWardEdge(j))/3.0
           Width = abs(EquatorWardEdge(j) - OCFLB(j))/2

           MaxP = max(maxval(iono_south_p(:,IONO_nPsi-j+1)),1.0e-15)
           iono_north_eflux(:,j) = &
                MulFac_ef*MaxP * &
                exp(-abs(Center-iono_north_theta(:,j))/Width) * &
                (0.375*cos(iono_north_psi(:,j)-cPi)+0.625)

           ! This is the way that seems to work
           iono_north_ave_e(:,j) = &
                iono_north_p(:,IONO_nPsi-j+1) / &
                (iono_north_rho(:,IONO_nPsi-j+1)+1.0e-32) * MulFac_ae

!           iono_north_ave_e(Poleward-2,j) = iono_north_ave_e(Poleward+1,j)
!           iono_north_ave_e(Poleward-1,j) = iono_north_ave_e(Poleward+1,j)

!           do i = Poleward-2, Equatorward+2
!           do i = Poleward, Equatorward
!              f = exp(-abs(float(i-Center))/float(width))
!              iono_north_eflux(i,j) = iono_north_eflux(i,j) * f
!           enddo

        enddo

        diffuse_ef = iono_north_eflux
        diffuse_ae = iono_north_ave_e

        discrete_ef = 0.0
        discrete_k  = 0.0

        ! This is from Jimmy's Paper on the Knight Relationship
        where (iono_north_p > 0) discrete_k = &
             (iono_north_rho**1.5) / iono_north_p
        ! Mirror the particles, since we are dealing with electrons and not
        ! ions.
        do j = 1, IONO_nPsi
           discrete_k(:,j) = discrete_k(:,IONO_nPsi-j+1)
        enddo
        where (iono_north_jr > 0.0) &
             discrete_ef = (iono_north_jr*1e6)*discrete_k
        discrete_ae = discrete_ef*MulFac_Dae
        discrete_ef = (iono_north_jr*1e6)*discrete_ef*MulFac_Def

        ! Let's add a little conductance on ANY not in the polar cap,
        ! so the code doesn't blow up
        do j = 1, IONO_nPsi
           do i = 1, IONO_nTheta
              if (abs(iono_north_jr(i,j)) > 0.0 .and. &
                   discrete_ef(i,j) < 5.0e-3) then
                 discrete_ef(i,j) = MulFac_Def/2.5 * &
                      (iono_north_jr(i,j)*1e6)**2*discrete_k(i,j)
              endif
           enddo
        enddo

        where (diffuse_ae < IONO_Min_Ave_E/2) diffuse_ae = IONO_Min_Ave_E/2
        where (discrete_ae < IONO_Min_Ave_E/2) discrete_ae = IONO_Min_Ave_E/2

        ! Let's weight the average energy by the number flux, which is ef/av
        iono_north_ave_e = &
             (diffuse_ef + discrete_ef) / &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae)

        ! The energy flux should be weighted by the average energy
        iono_north_eflux = &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae) * &
             iono_north_ave_e

        where (iono_north_ave_e < IONO_Min_Ave_E) &
             iono_north_ave_e = IONO_Min_Ave_E

!        ! Let's add a little conductance on ANY not in the polar cap,
!        ! so the code doesn't blow up
!        do j = 1, IONO_nPsi
!           do i = 1, IONO_nTheta
!              if (iono_north_p(i,j) <= 0.0) then
!                 iono_north_ave_e(i,j) = max(iono_north_ave_e(i,j),polarcap_avee)
!                 iono_north_eflux(i,j) = &
!                      max(iono_north_eflux(i,j),polarcap_eflux)
!              endif
!           enddo
!        enddo

     else

        iono_south_eflux = 0.0
        iono_south_ave_e = 1.0
        
        OCFLB = -1.0
        EquatorWardEdge = -1.0

        do j = 1, IONO_nPsi
           IsPeakFound = .false.
           MaxP = max(maxval(iono_south_p(:,IONO_nPsi-j+1)),1.0e-15)

           AuroraWidth = -1.0
           IsDone = .false.
           i = IONO_nTheta

           do while (.not. IsDone)

              if (iono_south_p(i,IONO_nPsi-j+1) > 0) then

                 if (OCFLB(j) == -1) OCFLB(j) = iono_south_theta(i,j)
                 AuroraWidth = OCFLB(j) - iono_south_theta(i,j)
                 MaxP = max(maxval(iono_south_p(:,IONO_nPsi-j+1)),1.0e-15)
                 iono_south_eflux(i,j) = MulFac_ef*MaxP

                 if (iono_south_p(i,IONO_nPsi-j+1)==MaxP) IsPeakFound = .true.

                 if (IsPeakFound .and. AuroraWidth >= MinWidth) then
                    EquatorWardEdge(j) = iono_south_theta(i,j)
                    IsDone = .true.
                 endif
              endif

              if (i == 1) IsDone = .true.
              i = i - 1

           enddo

           if (.not. IsPeakFound) then
              OCFLB(j) = cPi - MinWidth
              EquatorwardEdge(j) = cPi - MinWidth*2
           endif

        enddo

        smooth = 0.0
        do j = 1, IONO_nPsi
           do i = j-nHalfSmooth-1, j+nHalfSmooth-1
              smooth(j) = smooth(j) + OCFLB(mod(i+IONO_nPsi,IONO_nPsi)+1)
           enddo
        enddo
        OCFLB = smooth/(nHalfSmooth*2+1)
           
        smooth = 0.0
        do j = 1, IONO_nPsi
           do i = j-nHalfSmooth-1, j+nHalfSmooth-1
              smooth(j) = smooth(j) + &
                   EquatorWardEdge(mod(i+IONO_nPsi,IONO_nPsi)+1)
           enddo
        enddo
        EquatorWardEdge = smooth/(nHalfSmooth*2+1)

          
        do j = 1, IONO_nPsi
           Center = (OCFLB(j)*2.0 + EquatorWardEdge(j))/3.0
           Width = abs(EquatorWardEdge(j) - OCFLB(j))/2
           

           MaxP = max(maxval(iono_south_p(:,IONO_nPsi-j+1)),1.0e-15)
           iono_south_eflux(:,j) = &
                MulFac_ef*MaxP * &
                exp(-abs(Center-iono_south_theta(:,j))/Width) * &
                (0.375*cos(iono_south_psi(:,j)-cPi)+0.625)

           iono_south_ave_e(:,j) = &
                iono_south_p(:,IONO_nPsi-j+1) / &
                (iono_south_rho(:,IONO_nPsi-j+1)+1.0e-32) * MulFac_ae

        enddo

        diffuse_ef = iono_south_eflux
        diffuse_ae = iono_south_ave_e

        discrete_ef = 0.0
        discrete_k  = 0.0
        ! This is from Jimmy's Paper on the Knight Relationship
        where (iono_south_p > 0) discrete_k = &
             (iono_south_rho**1.5) / iono_south_p
        ! Reverse the particles again.
        do j = 1, IONO_nPsi
           discrete_k(:,j) = discrete_k(:,IONO_nPsi-j+1)
        enddo

        where (iono_south_jr > 0.5e-7) &
             discrete_ef = (iono_south_jr*1e6)*discrete_k
        discrete_ae = discrete_ef*MulFac_Dae
        discrete_ef = (iono_south_jr*1e6)*discrete_ef*MulFac_Def

        ! Let's add a little conductance on ANY not in the polar cap,
        ! so the code doesn't blow up
        do j = 1, IONO_nPsi
           do i = 1, IONO_nTheta
              if (abs(iono_south_jr(i,j)) > 0.0 .and. &
                   discrete_ef(i,j) < 5.0e-3) then
                 discrete_ef(i,j) = MulFac_Def/2.5 * &
                      (iono_south_jr(i,j)*1e6)**2*discrete_k(i,j)
              endif
           enddo
        enddo

        where (diffuse_ae < IONO_Min_Ave_E/2) diffuse_ae = IONO_Min_Ave_E/2
        where (discrete_ae < IONO_Min_Ave_E/2) discrete_ae = IONO_Min_Ave_E/2

!        write(*,*) "Discrete (south) : ",&
!             minval(discrete_ef), maxval(discrete_ef),&
!             minval(discrete_ae), maxval(discrete_ae)

        ! Let's weight the average energy by the number flux, which is ef/av
        iono_south_ave_e = &
             (diffuse_ef + discrete_ef) / &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae)

        ! The energy flux should be weighted by the average energy
        iono_south_eflux = &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae) * &
             iono_south_ave_e

        where (iono_south_ave_e < IONO_Min_Ave_E) &
             iono_south_ave_e = IONO_Min_Ave_E

        write(*,*) "Done with aurora"

!        do j = 1, IONO_nPsi
!           do i = 1, IONO_nTheta
!              if (iono_south_p(i,j) <= 0.0) then
!                 iono_south_ave_e(i,j) = max(iono_south_ave_e(i,j),polarcap_avee)
!                 iono_south_eflux(i,j) = &
!                      max(iono_south_eflux(i,j),polarcap_eflux)
        !              endif
!           enddo
!        enddo

     endif

  endif

  if (iModel.eq.8) then

     Beta = 0.1 !scale the flux to be smaller
     
     if (iBlock == 1) then 
        !north hemisphere
        iono_north_eflux = 0.0
        iono_north_ave_e = 1.0

        ! diffuse 
        ! rho is mass density, P is Pa. (These parameters are ray-traced averaged quantity,
        ! therefore they are not as at the source region (e.g.,plasmasheet), but overestimated?

        ! the rho, p are extracted from the ray tracing at Bmin
        F0 = Beta * sqrt(iono_north_rho*iono_north_p/(2*cPi*cElectronMass*cProtonMass*6.0))
        iono_north_eflux = F0*2*iono_north_p/(iono_north_rho+1.0e-32)*cProtonMass/6.0 ! W/m2
        iono_north_ave_e = 2*iono_north_p/(iono_north_rho+1.0e-32)*cProtonMass/6.0/1.6e-16 ! keV
        
        where(iono_north_ave_e > 20.0) &
             iono_north_ave_e = 20.0

        do j = 1, IONO_nPsi
           i = 1
           do while (iono_north_eflux(i,j) == 0.0 .and. i < Iono_nTheta)
              i = i + 1
           enddo
           if (i > 2) iono_north_eflux(i-1,j) = iono_north_eflux(i,j)* 0.66 
           if (i > 3) iono_north_eflux(i-2,j) = iono_north_eflux(i,j)* 0.33
           if (i > 4) iono_north_eflux(1:i-3,j) = PolarCap_EFlux
           if (i > 2) iono_north_ave_e(i-1,j) = iono_north_ave_e(i,j)
           if (i > 3) iono_north_ave_e(i-2,j) = iono_north_ave_e(i,j)
           if (i > 4) iono_north_ave_e(1:i-3,j) = PolarCap_AveE
        enddo
        
        where (iono_north_eflux < IONO_Min_EFlux) &
             iono_north_eflux = IONO_Min_EFlux

        diffuse_ef = iono_north_eflux
        diffuse_ae = iono_north_ave_e

        discrete_ef = 0.0
        discrete_ae= 0.0

        do j = 1, IONO_nPsi
           do i = 1, IONO_nTheta
              call sph_to_xyz(Radius, IONO_NORTH_Theta(i,j), IONO_NORTH_Psi(i,j), XyzIono_D)
              call get_planet_field(Time_Simulation, XyzIono_D, 'SMG', bIono_D)
              bIono = sqrt(sum(bIono_D**2))
              Rm = bIono/iono_north_beq(i,j)
              Te = iono_north_p(i,j)/(iono_north_rho(i,j)+1.0e-32)*cProtonMass /6.0
              if (iono_north_jr(i,j) .gt. 0.0 .and. F0(i,j) .gt. 0.0)then
                 eV = Te*(Rm-1)*log( (Rm-1)/(Rm-iono_north_jr(i,j)/1.6e-19/F0(i,j)))
                 
                 discrete_ef(i,j) = iono_north_jr(i,j)/1.6e-19* &
                      (2*Te + eV*(1-exp(-1*eV/Te/(Rm-1)))/(1+(1-1/Rm)*exp(-1*eV/Te/(Rm-1))))

                 discrete_ae(i,j) = discrete_ef(i,j)/(iono_north_jr(i,j)/1.6e-19)/1.6e-16 ! keV
              endif

           enddo
        enddo

        write(*,*)'max discrete/diffuse',maxval(discrete_ef),maxval(diffuse_ef)
        write(*,*)'max discrete/diffuse ave_e:',maxval(discrete_ae),maxval(diffuse_ae)
        write(*,*)'max rho,p,jr: ',maxval(iono_north_rho),maxval(iono_north_p),maxval(iono_north_jr)
        where (diffuse_ae < IONO_Min_Ave_E/2) diffuse_ae = IONO_Min_Ave_E/2
        where (discrete_ae < IONO_Min_Ave_E/2) discrete_ae = IONO_Min_Ave_E/2

        ! Let's weight the average energy by the number flux, which is ef/av
        iono_north_ave_e = &
             (diffuse_ef + discrete_ef) / &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae)

        ! The energy flux should be weighted by the average energy
        iono_north_eflux = &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae) * &
             iono_north_ave_e

        where (iono_north_ave_e < IONO_Min_Ave_E) &
             iono_north_ave_e = IONO_Min_Ave_E

!        ! Let's add a little conductance on ANY not in the polar cap,
!        ! so the code doesn't blow up
!        do j = 1, IONO_nPsi
!           do i = 1, IONO_nTheta
!              if (iono_north_p(i,j) <= 0.0) then
!                 iono_north_ave_e(i,j) = max(iono_north_ave_e(i,j),polarcap_avee)
!                 iono_north_eflux(i,j) = &
!                      max(iono_north_eflux(i,j),polarcap_eflux)
!              endif
!           enddo
!        enddo


     else

        iono_south_eflux = 0.0
        iono_south_ave_e = 1.0
        
        OCFLB = -1.0
        EquatorWardEdge = -1.0

        do j = 1, IONO_nPsi
           IsPeakFound = .false.
           MaxP = max(maxval(iono_south_p(:,IONO_nPsi-j+1)),1.0e-15)

           AuroraWidth = -1.0
           IsDone = .false.
           i = IONO_nTheta

           do while (.not. IsDone)

              if (iono_south_p(i,IONO_nPsi-j+1) > 0) then

                 if (OCFLB(j) == -1) OCFLB(j) = iono_south_theta(i,j)
                 AuroraWidth = OCFLB(j) - iono_south_theta(i,j)
                 MaxP = max(maxval(iono_south_p(:,IONO_nPsi-j+1)),1.0e-15)
                 iono_south_eflux(i,j) = MulFac_ef*MaxP

                 if (iono_south_p(i,IONO_nPsi-j+1)==MaxP) IsPeakFound = .true.

                 if (IsPeakFound .and. AuroraWidth >= MinWidth) then
                    EquatorWardEdge(j) = iono_south_theta(i,j)
                    IsDone = .true.
                 endif
              endif

              if (i == 1) IsDone = .true.
              i = i - 1

           enddo

           if (.not. IsPeakFound) then
              OCFLB(j) = cPi - MinWidth
              EquatorwardEdge(j) = cPi - MinWidth*2
           endif

        enddo

        smooth = 0.0
        do j = 1, IONO_nPsi
           do i = j-nHalfSmooth-1, j+nHalfSmooth-1
              smooth(j) = smooth(j) + OCFLB(mod(i+IONO_nPsi,IONO_nPsi)+1)
           enddo
        enddo
        OCFLB = smooth/(nHalfSmooth*2+1)
           
        smooth = 0.0
        do j = 1, IONO_nPsi
           do i = j-nHalfSmooth-1, j+nHalfSmooth-1
              smooth(j) = smooth(j) + &
                   EquatorWardEdge(mod(i+IONO_nPsi,IONO_nPsi)+1)
           enddo
        enddo
        EquatorWardEdge = smooth/(nHalfSmooth*2+1)


        ! since the ray-traced parameters are zero in the open region,
        ! F0 excludes the polar cap region here.
        ! diffuse flux is only specified below the open/close boundary
        ! rho is mass density, P is Pa
        F0 = Beta * sqrt(iono_south_rho*iono_south_p/(2*cPi*cElectronMass*cProtonMass*6.0))
        iono_south_eflux = F0*2*iono_south_p/(iono_south_rho+1.0e-32)*cProtonMass/6.0 ! W/m2
        iono_south_ave_e = 2*iono_south_p/(iono_south_rho+1.0e-32)*cProtonMass/6.0/1.6e-16 ! keV


        where (iono_south_ave_e > 20.0) &
             iono_south_ave_e = 20.0

        do j = 1, IONO_nPsi
           i = 1
           do while (iono_south_eflux(i,j) == 0.0 .and. i < Iono_nTheta)
              i = i + 1
           enddo
           if (i > 2) iono_south_eflux(i-1,j) = iono_south_eflux(i,j)* 0.66 
           if (i > 3) iono_south_eflux(i-2,j) = iono_south_eflux(i,j)* 0.33
           if (i > 4) iono_south_eflux(1:i-3,j) = PolarCap_EFlux
           if (i > 2) iono_south_ave_e(i-1,j) = iono_south_ave_e(i,j)
           if (i > 3) iono_south_ave_e(i-2,j) = iono_south_ave_e(i,j)
           if (i > 4) iono_south_ave_e(1:i-3,j) = PolarCap_AveE
        enddo

        where (iono_south_eflux < IONO_Min_EFlux) &
             iono_south_eflux = IONO_Min_EFlux

        
        diffuse_ef = iono_south_eflux
        diffuse_ae = iono_south_ave_e

        !debug
        !diffuse_ef = 0.0
        !diffuse_ae = 0.0

        discrete_ef = 0.0
        discrete_k  = 0.0

        ! Let's add a little conductance on ANY not in the polar cap,
        ! so the code doesn't blow up
        do j = 1, IONO_nPsi
           do i = 1, IONO_nTheta
              call sph_to_xyz(Radius, IONO_SOUTH_Theta(i,j), IONO_SOUTH_Psi(i,j), XyzIono_D)
              call get_planet_field(Time_Simulation, XyzIono_D, 'SMG', bIono_D)
              bIono = sqrt(sum(bIono_D**2))
              Rm = bIono/iono_south_beq(i,j)

              Te = iono_south_p(i,j)/(iono_south_rho(i,j)+1.0e-32)*cProtonMass /6.0

              ! F0 is zero in the cap region, cannot be divided by zero.
              if (iono_south_jr(i,j) .gt. 0.0 .and. F0(i,j) .gt. 0.0)then
                 eV = Te*(Rm-1)*log( (Rm-1)/(Rm-iono_south_jr(i,j)/1.6e-19/F0(i,j)))

                 discrete_ef(i,j) = iono_south_jr(i,j)/1.6e-19* &
                      (2*Te + eV*(1-exp(-1*eV/Te/(Rm-1)))/(1+(1-1/Rm)*exp(-1*eV/Te/(Rm-1))))

                 discrete_ae(i,j) = discrete_ef(i,j)/(iono_south_jr(i,j)/1.6e-19)/1.6e-16 !keV

              endif

           enddo
        enddo

        where (diffuse_ae < IONO_Min_Ave_E/2) diffuse_ae = IONO_Min_Ave_E/2
        where (discrete_ae < IONO_Min_Ave_E/2) discrete_ae = IONO_Min_Ave_E/2

!        write(*,*) "Discrete (south) : ",&
!             minval(discrete_ef), maxval(discrete_ef),&
!             minval(discrete_ae), maxval(discrete_ae)

        ! Let's weight the average energy by the number flux, which is ef/av
        iono_south_ave_e = &
             (diffuse_ef + discrete_ef) / &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae)

        ! The energy flux should be weighted by the average energy
        iono_south_eflux = &
             (diffuse_ef/diffuse_ae + discrete_ef/discrete_ae) * &
             iono_south_ave_e

        where (iono_south_ave_e < IONO_Min_Ave_E) &
             iono_south_ave_e = IONO_Min_Ave_E

        write(*,*) "Done with aurora"

!        do j = 1, IONO_nPsi
!           do i = 1, IONO_nTheta
!              if (iono_south_p(i,j) <= 0.0) then
!                 iono_south_ave_e(i,j) = max(iono_south_ave_e(i,j),polarcap_avee)
!                 iono_south_eflux(i,j) = &
!                      max(iono_south_eflux(i,j),polarcap_eflux)
!              endif
!           enddo
!        enddo

     endif
  end if


end subroutine FACs_to_fluxes


!-------------------------------------------------------------------------
! ionosphere_conductance
!
!
!
!-------------------------------------------------------------------------

subroutine ionosphere_conductance(Sigma0, SigmaH, SigmaP,               &
     SigmaThTh, SigmaThPs, SigmaPsPs,      &
     dSigmaThTh_dTheta, dSigmaThPs_dTheta, &
     dSigmaPsPs_dTheta,                    &
     dSigmaThTh_dPsi, dSigmaThPs_dPsi,     &
     dSigmaPsPs_dPsi,                      &
     Eflux, Ave_E,                         &
     Theta, Psi, nTheta, nPsi,             &
     dTheta, dPsi,                         &
     iModel, f107)

  !\
  ! This subroutine computes the height-integrated field-aligned and
  ! Hall and Pedersen conductances for the ionosphere at each
  ! location of the discretized solution domain.  The gradients of
  ! these quantities are also computed.
  !/

  use IE_ModMain
  use ModIonosphere
  implicit none

  integer :: nTheta,nPsi
  integer, intent(in) :: iModel
  real(real8_), intent(in)    :: f107
  real(real8_), dimension(1:IONO_nTheta,1:IONO_nPsi) ::  &
       Sigma0, SigmaH, SigmaP, &
       SigmaThTh, SigmaThPs, SigmaPsPs, &
       dSigmaThTh_dTheta, dSigmaThPs_dTheta, dSigmaPsPs_dTheta, &
       dSigmaThTh_dPsi, dSigmaThPs_dPsi, dSigmaPsPs_dPsi, &
       Eflux, Ave_E,                                            &
       Theta, Psi, sin_clat, cos_clat, sin_lon, cos_lon, cy,    &
       oSigmaH, oSigmaP, conv_SigmaH, conv_SigmaP, cos_SZA,     &
       tmp_x, tmp_y, tmp_z

  real(real8_), dimension(1:IONO_NTheta) :: dTheta
  real(real8_), dimension(1:IONO_NPsi)   :: dPsi

  integer :: i,j
  real(real8_) :: f107p53, f107p49
  real(real8_) :: sn, cs, sn2, cs2, cs3, cs4, C
  real(real8_) :: SigmaH_EUV, SigmaP_EUV, SigmaH_SCAT, SigmaP_SCAT, &
       SigmaH_STAR, SigmaP_STAR, SigmaH_EUV_2, SigmaP_EUV_2
  real(real8_) :: SigmaH_Particles, SigmaP_Particles, tau
  logical :: old

  real(real8_)    :: time_delay
  real(real8_)    :: cos_limit, meeting_value_h, meeting_value_p

  !--------------------------------------------------------------------------

  if (theta(1,1) < 2.0*IONO_Theta_0) then
     north = .true.
     tmp_x = IONO_NORTH_X
     tmp_y = IONO_NORTH_Y
     tmp_z = IONO_NORTH_Z
  else
     north = .false.
     tmp_x = IONO_SOUTH_X
     tmp_y = IONO_SOUTH_Y
     tmp_z = IONO_SOUTH_Z
  endif

!  if (use_comp(UA_)) then
!
!     Sigma0 = 1000.00
!
!     ! Use Conductances from the UAM, which are put into the following
!     ! variables
!
!     if (north) then
!        SigmaH = IONO_NORTH_SigmaH
!        SigmaP = IONO_NORTH_SigmaP
!     else
!        SigmaH = IONO_South_SigmaH
!        SigmaP = IONO_South_SigmaP
!     endif
!
!  else
!
     if (iModel > 1) then

        cos_SZA = (tmp_x*cosTHETATilt - tmp_z*sinTHETATilt) &
             / sqrt(tmp_x**2 + tmp_y**2 + tmp_z**2)

        ! We are going to need F10.7 ^ 0.53 and F10.7 ^ 0.49 a lot,
        ! So, let's just store them straight away:

        f107p53 = f107**0.53
        f107p49 = f107**0.49
        cos_limit = cos(70.0*cDegToRad)
        meeting_value_p = f107p49*(0.34*cos_limit+0.93*sqrt(cos_limit))
        meeting_value_h = f107p53*(0.81*cos_limit+0.54*sqrt(cos_limit))

     endif

     if (iModel.eq.0) then

        do j = 1, nPsi
           do i = 1, nTheta

              Sigma0(i,j) = 1000.00
              SigmaH(i,j) = 0.00
              SigmaP(i,j) = StarLightPedConductance

           enddo
        enddo

     endif

     if (iModel.eq.1) then

        do j = 1, nPsi
           do i = 1, nTheta

              Sigma0(i,j) = 1000.00
              SigmaH(i,j) = PolarCapPedConductance
              SigmaP(i,j) = StarLightPedConductance

           enddo
        enddo

     endif

     if (iModel.eq.2) then

        do j = 1, nPsi
           do i = 1, nTheta

!!$        !\
!!$        ! Rasmussen and Schunk model B (JGR, Vol. 92, pp. 4491-4504, 1987).
!!$        !/

              Sigma0(i,j) = 1000.00

              if (cos_SZA(i,j) > 0) then
                 SigmaH_EUV=f107p53*(0.81*cos_SZA(i,j)+0.54*sqrt(cos_SZA(i,j)))
                 SigmaP_EUV=f107p49*(0.34*cos_SZA(i,j)+0.93*sqrt(cos_SZA(i,j)))
                 SigmaH_SCAT = 1.00
                 SigmaP_SCAT = 0.50
                 if (cos_SZA(i,j) < cos_limit) then
                    SigmaH_EUV_2 = meeting_value_h *   &
                         exp(-((cos_SZA(i,j)-cos_limit)**2.0)*15.0)
                    SigmaP_EUV_2 = meeting_value_p *   &
                         exp(-((cos_SZA(i,j)-cos_limit)**2.0)*15.0)
                    SigmaH_EUV = (SigmaH_EUV + SigmaH_EUV_2)/2.0
                    SigmaP_EUV = (SigmaP_EUV + SigmaP_EUV_2)/2.0
                 endif
              else
                 SigmaH_EUV = meeting_value_h *   &
                      exp(-((cos_SZA(i,j)-cos_limit)**2.0)*15.0)
                 SigmaP_EUV = meeting_value_p *   &
                      exp(-((cos_SZA(i,j)-cos_limit)**2.0)*15.0)
                 SigmaH_SCAT = 1.00*(10.00**cos_SZA(i,j))
                 SigmaP_SCAT = 0.50*(10.00**cos_SZA(i,j))
              end if

              SigmaH_STAR = StarLightPedConductance*2.0
              SigmaP_STAR = StarLightPedConductance

              SigmaH(i,j) = sqrt(SigmaH_EUV*SigmaH_EUV +                     &
                   SigmaH_SCAT*SigmaH_SCAT +                                 &
                   SigmaH_STAR*SigmaH_STAR)
              SigmaP(i,j) = sqrt(SigmaP_EUV*SigmaP_EUV +                     &
                   SigmaP_SCAT*SigmaP_SCAT +                                 &
                   SigmaP_STAR*SigmaP_STAR)

           enddo
        enddo

     endif

     if (iModel.ge.3) then

        do j = 1, nPsi
           do i = 1, nTheta

              Sigma0(i,j) = 1000.00

              if (cos_SZA(i,j) > 0) then
                 SigmaH_EUV=f107p53*(0.81*cos_SZA(i,j)+0.54*sqrt(cos_SZA(i,j)))
                 SigmaP_EUV=f107p49*(0.34*cos_SZA(i,j)+0.93*sqrt(cos_SZA(i,j)))
                 SigmaH_SCAT = 1.00
                 SigmaP_SCAT = 0.50
                 if (cos_SZA(i,j) < cos_limit) then
                    SigmaH_EUV_2 = meeting_value_h *   &
                         exp(-((cos_SZA(i,j)-cos_limit)**2.0)*15.0)
                    SigmaP_EUV_2 = meeting_value_p *   &
                         exp(-((cos_SZA(i,j)-cos_limit)**2.0)*15.0)
                    SigmaH_EUV = (SigmaH_EUV + SigmaH_EUV_2)/2.0
                    SigmaP_EUV = (SigmaP_EUV + SigmaP_EUV_2)/2.0
                 endif
              else
                 SigmaH_EUV = meeting_value_h *   &
                      exp(-((cos_SZA(i,j)-cos_limit)**2.0)*15.0)
                 SigmaP_EUV = meeting_value_p *   &
                      exp(-((cos_SZA(i,j)-cos_limit)**2.0)*15.0)
                 SigmaH_SCAT = 1.00*(10.00**cos_SZA(i,j))
                 SigmaP_SCAT = 0.50*(10.00**cos_SZA(i,j))
              end if

              SigmaH_STAR = StarLightPedConductance*2.0
              SigmaP_STAR = StarLightPedConductance

              !\
              ! Use Robinson's Formula to convert the Ave_E and E_Flux to 
              ! SigmaP and SigmaH
              !/

              SigmaP_Particles = 40.0 * Ave_E(i,j) /                     &
                   (16.0 + Ave_E(i,j)*Ave_E(i,j))  *                     &
                   sqrt(EFlux(i,j)*1000.0)

              SigmaH_Particles = 0.45 * (Ave_E(i,j)**0.85) * SigmaP_Particles

              SigmaH(i,j) = sqrt(SigmaH_EUV*SigmaH_EUV + &
                   SigmaH_SCAT*SigmaH_SCAT + &
                   SigmaH_STAR*SigmaH_STAR + &
                   SigmaH_Particles*SigmaH_Particles)

              SigmaP_EUV = SigmaP_EUV*SigmaP_EUV + SigmaP_SCAT*SigmaP_SCAT + &
                   SigmaP_STAR*SigmaP_STAR

              SigmaP_Particles = SigmaP_Particles*SigmaP_Particles

              SigmaP(i,j) = sqrt(SigmaP_EUV + SigmaP_Particles)

           enddo

        enddo

     endif

     if (north) then

        ! Subsolar is i=nTheta ; j = 0
        ! Just in case we change this in the future, add noon and midnight to
        ! test for conductance

        if (SAVE_NORTH_SigmaH(nTheta,1) +                                     &
             SAVE_NORTH_SigmaH(nTheta,nPsi/2) .gt. 0.0) then

           ! We have "old" conductances

           old = .true.
           SigmaH = SAVE_NORTH_SigmaH
           SigmaP = SAVE_NORTH_SigmaP

        endif

     else

        ! Subsolar is i=0 ; j = 0
        ! Just in case we change this in the future, add noon and midnight to
        ! test for conductance

        if (SAVE_SOUTH_SigmaH(1,1) +                                         &
             SAVE_SOUTH_SigmaH(1,nPsi/2) .gt.0.0) then

           ! We have "old" conductances

           old = .true.
           SigmaH = SAVE_SOUTH_SigmaH
           SigmaP = SAVE_SOUTH_SigmaP

        endif

     endif

     if (north) then
        SAVE_NORTH_SigmaP = 0.0
        SAVE_NORTH_SigmaH = 0.0
     else
        SAVE_SOUTH_SigmaP = 0.0
        SAVE_SOUTH_SigmaH = 0.0
     endif

!  end if

  do j = 1, nPsi
     do i = 1, nTheta

        sn = sin(Theta(i,j))
        cs = cos(Theta(i,j))
        sn2= sn*sn
        cs2 = cs*cs
        cs3 = 1.00 + 3.00*cs2
        cs4 = sqrt(cs3)
        C = 4.00*Sigma0(i,j)*cs2 + &
             SigmaP(i,j)*sn2

        SigmaThTh(i,j) = Sigma0(i,j)*SigmaP(i,j)*cs3/C
        SigmaThPs(i,j) = 2.00*Sigma0(i,j)*SigmaH(i,j)* &
             cs*cs4/C
        SigmaPsPs(i,j) = SigmaP(i,j)+ &
             SigmaH(i,j)*SigmaH(i,j)* &
             sn2/C

        dSigmaThTh_dTheta(i,j) = 0.00
        dSigmaThTh_dPsi(i,j) = 0.00
        dSigmaThPs_dTheta(i,j) = 0.00
        dSigmaThPs_dPsi(i,j) = 0.00
        dSigmaPsPs_dTheta(i,j) = 0.00
        dSigmaPsPs_dPsi(i,j) = 0.00

     end do
  end do

  do j = 1, nPsi
     if (j > 1 .and. j < nPsi ) then 
        do i = 2, nTheta-1
           dSigmaThTh_dTheta(i,j) = (SigmaThTh(i+1,j)-SigmaThTh(i-1,j))/ &
                (dTheta(i))
           dSigmaThTh_dPsi(i,j) = (SigmaThTh(i,j+1)-SigmaThTh(i,j-1))/ &
                (dPsi(j))

           dSigmaThPs_dTheta(i,j) = (SigmaThPs(i+1,j)-SigmaThPs(i-1,j))/ &
                (dTheta(i))
           dSigmaThPs_dPsi(i,j) = (SigmaThPs(i,j+1)-SigmaThPs(i,j-1))/ &
                (dPsi(j))

           dSigmaPsPs_dTheta(i,j) = (SigmaPsPs(i+1,j)-SigmaPsPs(i-1,j))/ &
                (dTheta(i))
           dSigmaPsPs_dPsi(i,j) = (SigmaPsPs(i,j+1)-SigmaPsPs(i,j-1))/ &
                (dPsi(j))
        end do
     else if (j == 1) then
        do i = 2, nTheta-1
           dSigmaThTh_dTheta(i,j) = (SigmaThTh(i+1,j)-SigmaThTh(i-1,j))/ &
                (dTheta(i))
           dSigmaThTh_dPsi(i,j) = (SigmaThTh(i,j+1)-SigmaThTh(i,nPsi-1))/ &
                (dPsi(j))

           dSigmaThPs_dTheta(i,j) = (SigmaThPs(i+1,j)-SigmaThPs(i-1,j))/ &
                (dTheta(i))
           dSigmaThPs_dPsi(i,j) = (SigmaThPs(i,j+1)-SigmaThPs(i,nPsi-1))/ &
                (dPsi(j))

           dSigmaPsPs_dTheta(i,j) = (SigmaPsPs(i+1,j)-SigmaPsPs(i-1,j))/ &
                (dTheta(i))
           dSigmaPsPs_dPsi(i,j) = (SigmaPsPs(i,j+1)-SigmaPsPs(i,nPsi-1))/ &
                (dPsi(j))
        end do
     else
        do i = 2, nTheta-1
           dSigmaThTh_dTheta(i,j) = (SigmaThTh(i+1,j)-SigmaThTh(i-1,j))/ &
                (dTheta(i))
           dSigmaThTh_dPsi(i,j) = (SigmaThTh(i,2)-SigmaThTh(i,j-1))/ &
                (dPsi(j))

           dSigmaThPs_dTheta(i,j) = (SigmaThPs(i+1,j)-SigmaThPs(i-1,j))/ &
                (dTheta(i))
           dSigmaThPs_dPsi(i,j) = (SigmaThPs(i,2)-SigmaThPs(i,j-1))/ &
                (dPsi(j))

           dSigmaPsPs_dTheta(i,j) = (SigmaPsPs(i+1,j)-SigmaPsPs(i-1,j))/ &
                (dTheta(i))
           dSigmaPsPs_dPsi(i,j) = (SigmaPsPs(i,2)-SigmaPsPs(i,j-1))/ &
                (dPsi(j))
        end do
     end if
  end do

end subroutine ionosphere_conductance



subroutine Determine_Oval_Characteristics(Current_in, Theta_in, Psi_in, &
     Loc_of_Oval, Width_of_Oval, &
     Strength_of_Oval)

  !
  ! This routine calculates everything in radians away from the pole.
  !

  use ModIonosphere
  use ModKind
  implicit none

  !
  ! inputs:
  !

  real(real8_), dimension(1:IONO_nTheta, 1:IONO_nPsi), intent(in) :: &
       Current_in, Theta_in, Psi_in

  !
  ! Outputs:
  !

  real(real8_), dimension(1:IONO_nPsi), intent(out) :: &
       Loc_of_Oval, Width_of_Oval, Strength_of_Oval

  !
  ! Working Variables:
  !

  real(real8_), dimension(1:IONO_nTheta, 1:IONO_nPsi) :: &
       Current, Theta, Psi

  real(real8_), dimension(1:8) :: &
       max_fac, max_fac_colat, width, J_Save

  real(real8_)     :: day_colat, dusk_colat, midnight_colat, dawn_colat
  real(real8_)    :: day_fac, dusk_fac, midnight_fac, dawn_fac
  real(real8_)    :: noon_mid, dusk_dawn, day_strength, night_strength
  real(real8_)    :: mean_colat, dev_colat, sumFAC, Night_Width, Day_Width

  integer :: i, j, n, nloc, dJ, J_Start, J_End

  !
  ! Reverse the Arrays for Southern Hemisphere:
  !
  if (Theta_in(1,1) < cHalfPi) then
     Current = Current_in
     Theta   = Theta_in
     Psi     = Psi_in
     north   = .true.
  else
     do i = 1, IONO_nTheta
        do j = 1, IONO_nPsi
           Current(IONO_nTheta - (i-1), j) = Current_in(i,j)
           Theta(IONO_nTheta - (i-1), j)   = cPi - Theta_in(i,j)
           Psi(IONO_nTheta - (i-1), j)     = Psi_in(i,j)
        enddo
     enddo
     north   = .false.
  endif

  !
  ! Start the Oval Determination
  !

  dJ = IONO_nPsi/9

  do n = 1, 8 

     !
     ! figure out location of auroral oval:
     ! Let's start a little ways away from the pole...
     !

     nloc = 1
     J_Start = max(1,(n-1)*dJ)
     J_End   = min(n*dJ, IONO_nPsi)
     max_fac(n) = abs(Current(3,J_Start))
     max_fac_colat(n) = Theta(3,J_Start)
     J_Save(n) = J_Start 
     do j = J_Start, J_End
        do i = 4, IONO_nTheta
           if (Current(i,j) > max_fac(n)) then
              max_fac(n) = abs(Current(i,j))
              max_fac_colat(n) = Theta(i,j)
              J_Save(n) = j
              nloc = i
           endif
        enddo
     enddo
     !
     ! figure out width
     !

     width(n) = 0.0
     j = J_Save(n)
     do i = nloc, IONO_nTheta
        if (Current(i,j) > max_fac(n)/4.0) then
           width(n) = abs(max_fac_colat(n) - Theta(i,j))
        endif
     enddo

     if (width(n).le.(theta(2,1)-theta(1,1))) width(n) = max_fac_colat(n)/5.0

  enddo

  day_colat = (max_fac_colat(1) + max_fac_colat(8))/2.0
  dusk_colat = (max_fac_colat(2) + max_fac_colat(3))/2.0
  midnight_colat = (max_fac_colat(4) + max_fac_colat(5))/2.0
  dawn_colat = (max_fac_colat(6) + max_fac_colat(7))/2.0

  day_fac = (max_fac(1) + max_fac(8))/2.0
  dusk_fac = (max_fac(2) + max_fac(3))/2.0
  midnight_fac = (max_fac(4) + max_fac(5))/2.0
  dawn_fac = (max_fac(6) + max_fac(7))/2.0

  night_width = 0.0
  sumFAC = 0.0
  mean_colat = 0.0

  do n=1,8
     night_width = night_width + width(n) * max_fac(n)
     mean_colat = mean_colat + max_fac_colat(n) * max_fac(n)
     sumFAC = sumFAC + max_fac(n)
  enddo

  mean_colat = mean_colat/sumFAC
  Night_Width = Night_Width/sumFAC

  if (Night_Width > 6.0*cDegToRad) Night_Width=6.0*cDegToRad
  Day_Width = max(Night_Width/2.0,1.0*cDegToRad)

  if (mean_colat < 15.0*cDegToRad) then
     mean_colat = 15.0*cDegToRad
     dev_colat = 0.0
  else
     dev_colat = ((day_colat - mean_colat) * day_fac - &
          (midnight_colat - mean_colat) * midnight_fac) / &
          (day_fac + midnight_fac)

     ! Restrict auroral location a little bit:

     if (abs(dev_colat) > mean_colat/2.0) then
        dev_colat = dev_colat*mean_colat/2.0/abs(dev_colat)
     endif
  endif

  Day_Strength = dawn_fac
  Night_Strength = sumFAC

  !  dev_colat = 1.0*cDegToRad

  !  Day_Width = 2.5*cDegToRad
  !  Night_Width = Day_Width

  !  mean_colat = 2.0*cDegToRad

  do j=1,IONO_nPsi
     Loc_of_Oval(j)   = mean_colat - dev_colat*cos(Psi(1,j))
     Width_of_Oval(j) = Day_Width + &
          (Night_Width - Day_Width)*sin(Psi(1,j)/2.0)
     Strength_of_Oval(j) = Day_Strength + &
          (Night_Strength - Day_Strength)*sin(Psi(1,j)/2.0)
  enddo

end subroutine Determine_Oval_Characteristics


