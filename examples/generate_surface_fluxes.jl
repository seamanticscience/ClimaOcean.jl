# # Surface fluxes from prescribed ocean and atmosphere
#
# ClimaOcean uses bulk formulae to estimate the surface exchange of momentum,
# heat, and water vapor between the atmosphere and the ocean.
#
# This example demonstrates an example of the turbulent surface flux calculations performed in ClimaOcean
# using ECCO2 data for the ocean and JRA55 data for the atmosphere.
#
# For this example, we need ClimaOcean with its DataWrangling modules: ECCO2 and JRA55.
# We also need Oceananigans for the ImmersedBoundaryGrid and Field utilities, and CairoMakie to plot.

using ClimaOcean
using ClimaOcean.ECCO
using ClimaOcean.JRA55
using ClimaOcean.OceanSimulations
using Oceananigans
using Dates
using CairoMakie

# # Computing fluxes on the ECCO2 grid
#
# We start by building the ECCO2 grid, using `ECCO_bottom_height` to identify the bottom height.

grid = ECCO_immersed_grid()

# We visualize the bottom height of the ECCO grid using CairoMakie.

fig, ax, hm = heatmap(grid.immersed_boundary.bottom_height)
Colorbar(fig[1, 2], hm, height = Relative(3/4), label = "Depth (m)")

save("ECCO_continents.png", fig)

# ![](ECCO_continents.png)

# Next, we construct our atmosphere and ocean.
#
# The atmosphere is prescribed, downloaded from the JRA55 dataset.
# It contains:
# - zonal wind `u`
# - meridional wind `v`
# - surface temperature `T`
# - surface relative humidity `q`
# - surface pressure `p`
# - downwelling shortwave radiation
# - downwelling longwave radiation
#
# We load in memory only the first two time indices, corresponding to January 1st
# (at 00:00 AM and 03:00 AM), by using `JRA55NetCDFBackend(2)`.

atmosphere = JRA55PrescribedAtmosphere(; backend = JRA55NetCDFBackend(2))
ocean = ocean_simulation(grid, closure=nothing)

# Now that we have an atmosphere and ocean, we `set!` the ocean temperature and salinity
# to the ECCO2 data by first creating T, S metadata objects,

T_metadata = ECCOMetadatum(:temperature; date=DateTime(1993, 1, 1))
S_metadata = ECCOMetadatum(:salinity;    date=DateTime(1993, 1, 1))

# Note that if a date is not provided to `Metadata`, then the default Jan 1st, 1992 is used.
# To copy the ECCO state into `ocean.model`, we use `set!`,

set!(ocean.model; T=T_metadata, S=S_metadata)

# Finally, we construct a coupled model, which will compute fluxes during construction.
# We omit `sea_ice` so the model is ocean-only, and use the default `Radiation()` that
# uses the two-band shortwave (visible and UV) + longwave (mid and far infrared)
# decomposition of the radiation spectrum.

coupled_model = OceanSeaIceModel(ocean; atmosphere, radiation=Radiation(eltype))

# Now that the surface fluxes are computed, we can extract and visualize them.
# The turbulent fluxes are stored in `coupled_model.interfaces.atmosphere_ocean_interface.fluxes`.

fluxes = coupled_model.interfaces.atmosphere_ocean_interface.fluxes
λ, φ, z = nodes(fluxes.sensible_heat)

fig = Figure(size = (800, 800), fontsize = 15)

ax = Axis(fig[1, 1], title = "Sensible heat flux (W m⁻²)", ylabel = "Latitude")
heatmap!(ax, λ, φ, interior(fluxes.sensible_heat, :, :, 1); colormap = :bwr)

ax = Axis(fig[1, 2], title = "Latent heat flux (W m⁻²)")
heatmap!(ax, λ, φ, interior(fluxes.latent_heat, :, :, 1); colormap = :bwr)

ax = Axis(fig[2, 1], title = "Zonal wind stress (N m)", ylabel = "Latitude")
heatmap!(ax, λ, φ, interior(fluxes.x_momentum, :, :, 1); colormap = :bwr)

ax = Axis(fig[2, 2], title = "Meridional wind stress (N m)", xlabel = "Longitude")
heatmap!(ax, λ, φ, interior(fluxes.y_momentum, :, :, 1); colormap = :bwr)

ax = Axis(fig[3, 1], title = "Water vapor flux (kg m⁻² s⁻¹)", xlabel = "Longitude", ylabel = "Latitude")
heatmap!(ax, λ, φ, interior(fluxes.water_vapor, :, :, 1); colormap = :bwr)

save("surface_fluxes.png", fig)

# ![](surface_fluxes.png)
