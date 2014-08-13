#######################################
# TCL set of geodetic problem solvers #
#                                     #
# Dan I. Malta                        #
#######################################

# constants
set C_PI      [expr {acos(-1)}];                  # PI
set C_2PI     [expr {2.0 * $C_PI}];               # 2 * PI
set a0        6378137.0;                          # WGS84 semi major [m]
set invF      298.25722356366546517369570015525;  # WGS84 ellipsoid inverse flattening
set f         [expr {1.0 / $invF}];               # WGS84 ellipsoid flattening
set b0        [expr {$a0 * (1.0 - $f)}];          # WGS84 semi minor [m]

# @param  {numeric} origin point longitude [rad]
# @param  {numeric} origin point latitude [rad]
# @param  {numeric} destination point longitude [rad]
# @param  {numeric} destination point latitude [rad]
# @return {numeric} bearing from origin to destination, using vincenty algorithm [rad]
# @return {numeric} distance between origin and destination, using vincenty algorithm [m]
proc vincentyInverse {lon1 lat1 lon2 lat2} {
   # convergence criterion
   set eps  0.0000000000000001

   # flattening complementary
   set r  [expr {1.0 - $::f}]
   set L  [expr {$lon2 - $lon1}]
   
   #
   set tanU1 [expr {$r * tan($lat1)}]
   set tanU2 [expr {$r * tan($lat2)}]
   
   #
   set x [expr {atan($tanU1)}]
   set cosU1 [expr {cos($x)}]
   set sinU1 [expr {sin($x)}]

   #
   set x [expr {atan($tanU2)}]
   set cosU2 [expr {cos($x)}]
   set sinU2 [expr {sin($x)}]

   #
   set dCosU1CosU2 [expr {$cosU1 * $cosU2}]
   set dCosU1SinU2 [expr {$cosU1 * $sinU2}]
   set dSinU1SinU2 [expr {$sinU1 * $sinU2}]
   set dSinU1cosU2 [expr {$sinU1 * $cosU2}]

   #
   set lambda    $L
   set lambdaP   $::C_2PI
   set iterLimit 0

   while {abs($lambda - $lambdaP) > $eps && $iterLimit < 100} {
      #
      set sinLambda [expr {sin($lambda)}]
      set cosLambda [expr {cos($lambda)}]

      #
      set sinSigma [expr {hypot($cosU2 * $sinLambda, $dCosU1SinU2 - $dSinU1cosU2 * $cosLambda)}]
      #set sinSigma [expr {sqrt(($cosU2 * $sinLambda) * ($cosU2 * $sinLambda) + ($dCosU1SinU2 - $dSinU1cosU2 * $cosLambda) * ($dCosU1SinU2 - $dSinU1cosU2 * $cosLambda))}]
      if {$sinSigma == 0} {
         return [list 0.0 0.0]
      }

      #
      set cosSigma   [expr {$dSinU1SinU2 + $dCosU1CosU2 * $cosLambda}]
      set sigma      [expr {atan2($sinSigma, $cosSigma)}]
      set sinAlpha   [expr {$dCosU1CosU2 * $sinLambda / $sinSigma}]
      set cosSqAlpha [expr {1.0 - $sinAlpha * $sinAlpha}]

      # is equatorial?
      if {$cosSqAlpha == 0} {
         set cos2SigmaM 0.0
      } else {
        set cos2SigmaM [expr {$cosSigma - 2.0 * $dSinU1SinU2 / $cosSqAlpha}]
      }

      #
      set C [expr {$::f / 16.0  * $cosSqAlpha * (4.0 + $::f * (4.0 - 3.0 * $cosSqAlpha))}]

      set lambdaP $lambda
      set lambda  [expr {$L + (1.0 - $C) * $::f * $sinAlpha * ($sigma + $C * $sinSigma * ($cos2SigmaM + $C * $cosSigma * (-1.0 + 2.0 * $cos2SigmaM * $cos2SigmaM)))}]

      # increase counter
      incr iterLimit 1
   }

   #
   set uSq        [expr {$cosSqAlpha * ($::a0 * $::a0 - $::b0 * $::b0) / ($::b0 * $::b0)}]
   set A          [expr {1.0 + $uSq / 16384.0 * (4096.0 + $uSq * (-768.0 + $uSq * (320.0 - 175.0 * $uSq)))}]
   set B          [expr {$uSq / 1024.0 * (256.0 + $uSq * (-128.0 + $uSq * (74.0 - 47.0 * $uSq)))}]
   set deltaSigma [expr {$B * $sinSigma * ($cos2SigmaM + $B / 4.0 * ($cosSigma * (-1.0 + 2.0 * $cos2SigmaM * $cos2SigmaM) - \
                         $B / 6.0 + $cos2SigmaM * (-3.0 + 4.0 * $sinSigma * $sinSigma) * (-3.0 + 4.0 * $cos2SigmaM * $cos2SigmaM)))}]

   #
   set xo_distance [expr {$::b0 * $A * ($sigma - $deltaSigma)}]
   set xo_bearing  [expr {atan2($cosU2 * $sinLambda, $dCosU1SinU2 - $dSinU1cosU2 * $cosLambda)}]
   if {$xo_bearing < 0.0} {
      set xo_bearing [expr {$xo_bearing + $::C_2PI}]
   }

   #
   return [list $xo_bearing $xo_distance]
}

# @param  {numeric} origin point longitude [rad]
# @param  {numeric} origin point latitude [rad]
# @param  {numeric} distance from origin point [m]
# @param  {numeric} bearing from origin point, relative to north [rad]
# @return {numeric} latitude of destination point, using vincenty algorithm [rad]
# @return {numeric} longitude of destination point, using vincenty algorithm [m]
proc vincentyDirect {xi_lat xi_lon xi_range xi_bearing} {
   # convergence criterion
   set eps  0.0000000000000001
   
   # flattening complementary
   set r  [expr {1.0 - $::f}]
   
   #
   set sinAlpha1 [expr {sin($xi_bearing)}]
   set cosAlpha1 [expr {cos($xi_bearing)}]

   #
   set tanU1 [expr {$r * tan($xi_lat)}]
   set cosU1 [expr {1.0 / sqrt(1.0 + $tanU1 * $tanU1)}]
   set sinU1 [expr {$tanU1 * $cosU1}]
   
   #
   set sigma1     [expr {atan2($tanU1, $cosAlpha1)}]
   set sinAlpha   [expr {$cosU1 * $sinAlpha1}]
   set cosSqAlpha [expr {1.0 - $sinAlpha * $sinAlpha}]
   set uSq        [expr {$cosSqAlpha * ($::a0 * $::a0 - $::b0 * $::b0) / ($::b0 * $::b0)}]
   set A          [expr {1.0 + $uSq / 16384.0 * (4096.0 + $uSq * (-768.0 + $uSq * (320.0 - 175.0 * $uSq)))}]
   set B          [expr {$uSq / 1024.0 * (256.0 + $uSq * (-128.0 + $uSq * (74.0 - 47.0 * $uSq)))}]
   
   #
   set sigma      [expr {$xi_range / ($::b0 * $A)}]
   set sigmaP     $::C_2PI
   set sinSigma   [expr {sin($sigma)}]
   set cosSigma   [expr {cos($sigma)}]
   set cos2SigmaM [expr {cos(2.0 * $sigma1 + $sigma)}]
   
   set iterLimit 0

   while {abs($sigma - $sigmaP) > $eps && $iterLimit < 100} {
      #
      set cos2SigmaM [expr {cos(2.0 * $sigma1 + $sigma)}]
      set sinSigma   [expr {sin($sigma)}]
      set cosSigma   [expr {cos($sigma)}]

      #
      set cos2SigmaSq [expr {$cos2SigmaM * $cos2SigmaM}]
      set deltaSigma  [expr {$B * $sinSigma * ($cos2SigmaM + $B / 4.0 * ($cosSigma * (-1.0 + 2.0 * $cos2SigmaSq) - \
                                               $B / 6.0 * $cos2SigmaM * (-3.0 + 4.0 * $sinSigma * $sinSigma) * (-3.0 + 4.0 * $cos2SigmaSq)))}]
      set sigmaP $sigma
      set sigma [expr {$deltaSigma + $xi_range / ($::b0 * $A)}]

      # increase counter
      incr iterLimit 1
   }

   #
   set tmp    [expr {$sinU1 * $sinSigma - $cosU1 * $cosSigma * $cosAlpha1}]
   set lat2   [expr {atan2($sinU1 * $cosSigma + $cosU1 * $sinSigma * $cosAlpha1, $r * hypot($sinAlpha, $tmp))}]
   set lambda [expr {atan2($sinSigma * $sinAlpha1, $cosU1 * $cosSigma - $sinU1 * $sinSigma * $cosSqAlpha)}]
   set C      [expr {$::f / 16.0 * $cosSqAlpha * (4.0 + $::f * (4.0 - 3.0 * $cosSqAlpha))}]
   set L      [expr {$lambda - (1.0 - $C) * $::f * $sinAlpha * ($sigma + $C * $sinSigma * ($cos2SigmaM + $C * $cosSigma * (-1.0 + 2.0 * $cos2SigmaM * $cos2SigmaM)))}]
   set lon2   [expr {$xi_lon + $L}]

   #
   return [list $lat2 $lon2]
}


# Earth north and east radius at a given latitude
# input is in radians, output is in meters

# @param  {numeric} latitude [rad]
# @return {numeric} north radius, assuming oblate spheroid [m]
# @return {numeric} east radius, assuming oblate spheroid [m]
proc earthRadius {xi_latitude} {
    #constants
    set C_A     6371837.0
    set C_E_SQ  0.006694380025164
    
    # east and north radius [m]
    set sinLat      [expr {sin($xi_latitude)}]
    set sinLatSqr   [expr {$sinLat * $sinLat}]
    set common      [expr {1.0 - $C_E_SQ * $sinLatSqr}]
    set xo_north    [expr {$C_A * (1.0 - $C_E_SQ) / sqrt($common * $common * $common)}]
    set xo_east     [expr {$C_A / sqrt($common)}]
    
    # output
    return [list $xo_north $xo_east]
}

# @param  {numeric} origin point longitude [rad]
# @param  {numeric} origin point latitude [rad]
# @param  {numeric} distance from origin point [m]
# @param  {numeric} bearing from origin point, relative to north [rad]
# @return {numeric} latitude of destination point, using "flat earth" assumption [rad]
# @return {numeric} longitude of destination point, using "flat earth" assumption [m]
proc pointCalc {xi_latitude xi_longitude xi_range xi_bearing} {
    # origin point east and north radius [m]
    lassign [earthRadius $xi_latitude] northRadius eastRadius

    # calculate point latitude
    set xo_latitude [expr {asin(sin($xi_latitude) * cos($xi_range / $northRadius) + cos($xi_latitude) * sin($xi_range / $northRadius) * cos($xi_bearing))}]

    # calculate point longitude
    set xo_longitude [expr {$xi_longitude + atan2(sin($xi_bearing) * sin($xi_range / $eastRadius) * cos($xi_latitude), cos($xi_range / $eastRadius) - sin($xi_latitude) * sin($xo_latitude))}]

    # output
    return [list $xo_latitude $xo_longitude]
}
