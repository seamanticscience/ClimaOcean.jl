module GLODAP

"""
    module GLODAP

    Tools to download and manipulate GLODAP data.
"""

export GLODAPMetadatum, GLODAP_immersed_grid, adjusted_GLODAP_tracers, initialize!
export GLODAP2Climatology

using Oceananigans
using ClimaOcean
using NCDatasets
using Dates
using Adapt
using Scratch
using Downloads

using Oceananigans.DistributedComputations: @root

using ClimaOcean.DataWrangling:
    netrc_downloader,
    BoundingBox,
    metadata_path,
    Celsius,
    Metadata,
    Metadatum,
    download_progress

using KernelAbstractions: @kernel, @index

using Dates: year, month, day

using Tar, CodecZlib

import Oceananigans: location

import ClimaOcean.DataWrangling:
    default_download_directory,
    all_dates,
    metadata_filename,
    download_dataset,
    temperature_units,
    dataset_variable_name,
    metaprefix,
    longitude_interfaces,
    latitude_interfaces,
    z_interfaces,
    is_three_dimensional,
    inpainted_metadata_path,
    reversed_vertical_axis,
    default_mask_value,
    available_variables

download_GLODAP_cache::String = ""
function __init__()
    global download_GLODAP_cache = @get_scratch!("GLODAP")
end

# Datasets
struct GLODAP2Climatology end

function default_download_directory(::GLODAP2Climatology)
    path = joinpath(download_GLODAP_cache, "v2", "data")
    return mkpath(path)
end

Base.size(::GLODAP2Climatology, variable) = (360, 180, 33)

temperature_units(::GLODAP2Climatology) = Celsius()
default_mask_value(::GLODAP2Climatology) = 0
reversed_vertical_axis(::GLODAP2Climatology) = true

const GLODAP2_url = "https://www.ncei.noaa.gov/archive/archive-management-system/OAS/bin/prd/jquery/download/286118.1.1.tar.gz"
#const GLODAP2_url = "https://www.nodc.noaa.gov/archive/arc0107/0162565/1.1/data/0-data/mapped/GLODAPv2.2016b_MappedClimatologies.tar.gz"
#const GLODAP2_url = "https://glodap.info/glodap_files/v2.2023/GLODAPv2.2016b.MappedProduct.tar.gz"

# The whole range of dates in the different dataset datasets
all_dates(::GLODAP2Climatology) = all_dates(dataset, nothing)
all_dates(::GLODAP2Climatology, variable) = DateTime(2002, 6, 1)

longitude_interfaces(::GLODAP2Climatology) = (0, 360)
latitude_interfaces(::GLODAP2Climatology) = (-90, 90)

z_interfaces(::GLODAP2Climatology) = [
    -6000,
    -5500,
    -5000,
    -4500,
    -4000,
    -3500,
    -3000,
    -2500,
    -2000,
    -1750,
    -1500,
    -1400,
    -1300,
    -1200,
    -1100,
    -1000,
    -900,
    -800,
    -700,
    -600,
    -500,
    -400,
    -300,
    -250,
    -200,
    -150,
    -125,
    -100,
    -75,
    -50,
    -30,
    -20,
    -10,
    0,
]
available_variables(::GLODAP2Climatology) = GLODAP2_dataset_variable_names

GLODAP2_dataset_variable_names = Dict(
    :temperature                => "temperature",
    :salinity                   => "salinity",
    :dissolved_inorganic_carbon => "TCO2",
    :alkalinity                 => "TAlk",
    :phosphate                  => "PO4",
    :nitrate                    => "NO3",
    :silicate                   => "silicate",
    :disssolved_oxygen          => "oxygen",
    :potential_pH               => "pHts25p0",
    :pH                         => "pHtsinsitutp",
    :saturation_state_aragonite => "OmegaA",
    :saturation_state_calcite   => "OmegaC",
    :antropogenic_carbon        => "Cant",
    :natural_carbon             => "PI_TCO2",
)

GLODAP_location = Dict(
    :temperature                => (Center, Center, Center),
    :salinity                   => (Center, Center, Center),
    :dissolved_inorganic_carbon => (Center, Center, Center),
    :alkalinity                 => (Center, Center, Center),
    :phosphate                  => (Center, Center, Center),
    :nitrate                    => (Center, Center, Center),
    :silicate                   => (Center, Center, Center),
    :dissolved_oxygen           => (Center, Center, Center),
    :potential_pH               => (Center, Center, Center),
    :pH                         => (Center, Center, Center),
    :saturation_state_aragonite => (Center, Center, Center),
    :saturation_state_calcite   => (Center, Center, Center),
    :antropogenic_carbon        => (Center, Center, Center),
    :natural_carbon             => (Center, Center, Center),
)

const GLODAPMetadata{D} = Metadata{<:GLODAP2Climatology, D}
const GLODAPMetadatum   = Metadatum{<:GLODAP2Climatology}

"""
    GLODAPMetadatum(name;
                  date = first_date(GLODAP2Climatology(), name),
                  dir = download_GLODAP_cache)

An alias to construct a [`Metadatum`](@ref) of `GLODAP2Climatology()`.
"""
function GLODAPMetadatum(name;
                       date = first_date(GLODAP2Climatology(), name),
                       dir = download_GLODAP_cache)

    return Metadatum(name; date, dir, dataset=GLODAP2Climatology())
end

metaprefix(::GLODAPMetadata) = "GLODAPMetadata"

# File name generation specific to each dataset
function metadata_filename(metadata::Metadatum{<:GLODAP2Climatology})
    prefix    = "GLODAPv2.2016b"
    shortname = dataset_variable_name(metadata)
    return prefix * "." * shortname * ".nc"
end

# Convenience functions
dataset_variable_name(data::Metadata{<:GLODAP2Climatology}) = GLODAP2_dataset_variable_names[data.name]
location(data::GLODAPMetadata) = GLODAP_location[data.name]

is_three_dimensional(data::GLODAPMetadata) = true

# URLs for the GLODAP datasets specific to each dataset
metadata_url(m::Metadata{<:GLODAP2Climatology}) = GLODAP2_url * "monthly/" * dataset_variable_name(m) * "/" * metadata_filename(m)

#function metadata_url(m::Metadata{<:GLODAP2Climatology})
#    year = string(Dates.year(m.dates))
#    return GLODAP4_url * dataset_variable_name(m) * "/" * year * "/" * metadata_filename(m)
#end

function download_dataset(metadata::GLODAPMetadata)
    dir          = metadata.dir
    tarball_path = joinpath(replace(dir,"/data"=>""), "GLODAP2.tar.gz")

    # Download the tar.gz file if it doesn't exist
    if !isfile(tarball_path)
        @info "Downloading tarball from $GLODAP2_url to $tarball_path..."
        Downloads.download(GLODAP2_url, tarball_path; progress=download_progress)
    else
        @info "GLODAP2 tarball already exists at $tarball_path, skipping download."
    end

    # Extract the tar.gz file
    @info "Extracting $tarball_path to $dir..."
    # Remove previously extracted directories or existing nc files in metadata.dir to avoid confusion
    foreach(x -> rm(x; recursive=true, force=true), readdir(dir, join=true))

    # Extract only .nc files from the tarball into the embedded directory structure of the tarball
    open(tarball_path) do tmp
        gzstream = GzipDecompressorStream(tmp)
        Tar.extract(
                    h -> h.type == :file && 
                    endswith(lowercase(h.path), ".nc"),
                    gzstream, 
                    dir,
                   )
    end

    # find the .nc files within the tarball's embedded directory structure and move them to dir
    for (root, _, files) in walkdir(dir)
        for fname in files
            if endswith(lowercase(fname), ".nc")
                src = joinpath(root, fname)
                destination_file = joinpath(dir, basename(fname))

                mv(src, destination_file; force=true)
            end
        end
    end
    return nothing
end

function inpainted_metadata_filename(metadata::GLODAPMetadata)
    original_filename = metadata_filename(metadata)
    without_extension = original_filename[1:end-3]
    return without_extension * "_inpainted.jld2"
end

inpainted_metadata_path(metadata::GLODAPMetadata) = joinpath(metadata.dir, inpainted_metadata_filename(metadata))

end # Module
