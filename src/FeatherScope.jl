module FeatherScope

# Standard Library
using Dates: DateTime, @dateformat_str, format
using Mmap: mmap
using Statistics: mean
using Printf: @sprintf

# Public Packages
import VideoIO
using VideoIO: openvideo
using Images: Gray
using MAT: matopen
using GaussianMixtures: GMM, llpg

# Private Packages
using GLUtilities: find_all_edge_triggers, find_first_edge_trigger

export
    # Constants
    FEATHER_VIDEO_DAQ_FS,

    # Types
    FeatherAdcChannelResults,

    # Functions
    align_feather_files,
    check_dropped_frames,
    check_featherdat_offset,
    crop_clip_video,
    feather_file_dt,
    find_exposed_periods,
    find_sync_edges,
    find_shutter_openings,
    frame_intensities,
    guess_shutter_frames,
    load_featherscope_adc_reads,
    make_feather_dt_str,
    make_feather_vidname,
    make_feather_daqname,
    make_feather_timestampsname,
    read_feather_video_daq_file,
    read_feather_timestamps,
    sync_exposed_video_daq

include("adc.jl")
include("sync.jl")

end # module
