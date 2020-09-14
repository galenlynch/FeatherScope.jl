const FEATHER_VIDEO_DAQ_FS = 48000.0
const FEATHER_SYNC_HIGH = 3.3
const FEATHER_SHUTTER_HIGH = 5.0

const FEATHER_DT_REG = r"(\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2})"
const FEATHER_VIDEO_DAQ_REG = r"(\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2})_DAQ\.mat"
const FEATHER_VIDEO_REG = r"(\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2})_video\.avi"
const FEATHER_TIMESTAMP_REG = r"(\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2})_timestamps\.mat"
const FEATHER_DTF = dateformat"YYYY_mm_dd_HH_MM_SS"

feather_file_dt(str, reg = FEATHER_VIDEO_REG) = DateTime(match(reg, str)[1], FEATHER_DTF)

make_feather_dt_str(dt::DateTime) = format(dt, FEATHER_DTF)
make_feather_vidname(dt::DateTime) = make_feather_dt_str(dt) * "_video.avi"
make_feather_daqname(dt::DateTime) = make_feather_dt_str(dt) * "_DAQ.mat"
make_feather_timestampsname(dt::DateTime) = make_feather_dt_str(dt) * "_timestamps.mat"

function read_feather_video_daq_file(matfilename::AbstractString)
    output_buff =
        matopen(x -> read(x, "outputBuffer"), matfilename)::Matrix{Float64}
    micdata = view(output_buff, :, 1)
    syncdata = view(output_buff, :, 2)
    shutterdata = view(output_buff, :, 4)
    micdata, syncdata, shutterdata
end

function read_feather_timestamps(matfilename::AbstractString)
    tsmat = matopen(x -> read(x, "tOut"), matfilename)::Matrix{Float64}
    dropdims(tsmat, dims = 2)
end

function check_dropped_frames(timestamps; framerate = 30.0, tol = 0.1)
    max_diff = (1 + tol) / framerate
    @inbounds for frameno in 2:length(timestamps)
        if timestamps[frameno] - timestamps[frameno - 1] > max_diff
            return true
        end
    end
    return false
end

function find_sync_edges(sync_pulses::AbstractVector{<:Number},
                         sync_high::Number = FEATHER_SYNC_HIGH,)
    find_all_edge_triggers(sync_pulses, sync_high / 2)
end

find_sync_edges(sync_data::AbstractMatrix, args...) =
    find_sync_edges(view(sync_data, 2, :), args...)

function find_shutter_edges(shutter_signal::AbstractVector{<:Number},
                               shutter_high = FEATHER_SHUTTER_HIGH)
    find_all_edge_triggers(shutter_signal, shutter_high / 2)
end

find_shutter_edges(sync_data::AbstractMatrix, args...) =
    find_shutter_edges(view(sync_data, 3, :), args...)

function two_gaussian_thresholds(data, thresh_stds)
    xs = reshape(data, :, 1)
    gmm = GMM(2, xs)
    offno = argmin(gmm.μ)
    onno = ifelse(offno == 1, 2, 1)
    off_mean = gmm.μ[offno]
    off_std = sqrt(gmm.Σ[offno])
    on_mean = gmm.μ[onno]
    on_std = sqrt(gmm.Σ[onno])

    # Use the fit gaussians to set a threshold on intensities of frames during
    # which the shutter was open (on) or closed (off).
    exposed_thresh = off_mean + thresh_stds * off_std # intensities above this are exposed
    dark_thresh = on_mean - thresh_stds * on_std # intensities below this are unexposed

    exposed_thresh, dark_thresh
end

"""
function find_exposed_periods(
    sync_indices::AbstractVector{<:Integer},
    shutter_open_periods::AbstractMatrix{<:Integer},
    image_intensities::AbstractVector{<:Number},
    n_sync_samples::Integer,
    exposed_thresh::Number,
    dark_thresh::Number;
    skip_shutters = 0
) -> exposed_frame_periods, exposed_sync_periods

Finds the exposed video frame numbers, and the corresponding sync pulse numbers.
Note that `exposed_sync_periods` may refer to indices larger than the length of
`sync_indices`, indicating that the last frame of the video occurred after the
sync pulses were no longer recorded.
"""
function find_exposed_periods(
    sync_indices::AbstractVector{<:Integer},
    shutter_open_periods::AbstractMatrix{<:Integer},
    image_intensities::AbstractVector{<:Number},
    n_sync_samples::Integer,
    exposed_thresh::Number,
    dark_thresh::Number;
    skip_shutters = 0
)
    nframe = length(image_intensities)
    nopen = size(shutter_open_periods, 2)
    @show size(shutter_open_periods)
    @show nopen
    startopen = shutter_open_periods[1, 1] == 1
    skipped_openings =  div(skip_shutters + startopen, 2)
    nout = nopen - skipped_openings
    exposed_frame_periods = similar(shutter_open_periods, 2, nout)
    shutterno = skip_shutters + startopen
    exposed_sync_periods = similar(exposed_frame_periods)
    search_startopen = !xor(iseven(skip_shutters), startopen)
    shutterno = skip_shutters + startopen + 1
    if search_startopen
        exposed_frame_search = 1
        exposed_frame_periods[1, 1] = 1
        dark_frame_search =
            find_first_edge_trigger(image_intensities, dark_thresh, <=) + 1
        exposed_frame_periods[2, 1], exposed_sync_periods[2, 1] =
            find_fully_exposed_frame(
                sync_indices,
                shutter_open_periods[shutterno],
                image_intensities,
                exposed_thresh,
                dark_thresh,
                dark_frame_search,
                exposed_frame_search,
                -1
            )
        exposed_sync_periods[1, 1] = exposed_sync_periods[2, 1] -
            exposed_frame_periods[2, 1] + 1
        shutterno += 1
        outno = 2
    else
        dark_frame_search = 1
        outno = 1
    end
    for openno in outno:nout
        exposed_frame_search =
            dark_frame_search + find_first_edge_trigger(
                image_intensities[dark_frame_search:end], exposed_thresh
            )

        exposed_frame_periods[1, openno], exposed_sync_periods[1, openno] =
            find_fully_exposed_frame(
                sync_indices,
                shutter_open_periods[shutterno],
                image_intensities,
                exposed_thresh,
                dark_thresh,
                dark_frame_search,
                exposed_frame_search,
                1
            )
        shutterno += 1
        if shutter_open_periods[shutterno] < n_sync_samples
            dark_frame_search =
                exposed_frame_search + find_first_edge_trigger(
                    image_intensities[exposed_frame_search:end], dark_thresh, <=
                )

            exposed_frame_periods[2, openno], exposed_sync_periods[2, openno] =
                find_fully_exposed_frame(
                    sync_indices,
                    shutter_open_periods[shutterno],
                    image_intensities,
                    exposed_thresh,
                    dark_thresh,
                    dark_frame_search,
                    exposed_frame_search,
                    -1
                )
            shutterno += 1
        else
            exposed_frame_periods[2, openno] = nframe
            exposed_sync_periods[2, openno] = exposed_sync_periods[1, openno] +
                nframe - exposed_frame_periods[1, openno]
        end
    end
    exposed_frame_periods, exposed_sync_periods
end

function guess_shutter_frames(
    sync_indices::AbstractVector{<:Integer},
    shutter_open_periods::AbstractMatrix{<:Integer},
    image_intensities::AbstractVector{<:Number},
    n_sync_samples::Integer;
    thresh_stds::Number = 3.0,
)
    exposed_thresh, dark_thresh = two_gaussian_thresholds(image_intensities, thesh_stds)
    guess_shutter_frames(
        sync_indices,
        shutter_index,
        image_intensities,
        exposed_thresh,
        dark_thresh,
        n_sync_samples
    )
end

function find_fully_exposed_frame(
    sync_indices,
    shutter_edge,
    image_intensities,
    exposed_thresh,
    dark_thresh,
    dark_frame_search,
    exposed_frame_search,
    dark_search_direction = 1
)
    nframe = length(image_intensities)
    # Assuming the shutter is initially closed, work from the edges of the
    # recording to figure out when the shutter was opened
    dark_search_dir = sign(dark_search_direction)
    dark_search_dir == 0 && throw(ArgumentError("invalid direction"))
    if dark_search_dir == 1
        dark_comp = <
        exposed_comp = >
    else
        dark_comp = >
        exposed_comp = <
    end
    exposed_edge_no = dark_frame_search # First frame that looks like an exposed frame
    while (
        dark_comp(exposed_edge_no, exposed_frame_search) &&
        image_intensities[exposed_edge_no] < exposed_thresh
    )
        exposed_edge_no += dark_search_dir
    end
    dark_edge_no = exposed_frame_search # Last frame that looks like an unexposed frame
    while (
        exposed_comp(dark_edge_no, dark_frame_search) &&
        image_intensities[dark_edge_no] > dark_thresh
    )
        dark_edge_no -= dark_search_dir
    end
    if exposed_edge_no == exposed_frame_search || dark_edge_no == dark_frame_search
        error("Did not find an edge")
    end

    partial_sync_no = searchsortedlast(sync_indices, shutter_edge)
    partial_sync_no == 0 && error("Latch opened before sync pulses")
    partial_sync_no == nframe && error("No fully exposed frame")

    shutter_gap = abs(exposed_edge_no - dark_edge_no)
    if shutter_gap == 2
        # If there is a frame in between the exposed frames and dark frames,
        # then that frame is most likely the frame in which the shutter was
        # opened, and the first frame that looks exposed probably was fully
        # exposed
        fully_exposed_frame = exposed_edge_no
    elseif shutter_gap == 1
        # Intensity is too similar to either open or closed to easily call.
        # Look at what fraction of the integration period had the shutter open
        # to decide which frame was partially exposed.
        closed_samples = shutter_edge - sync_indices[partial_sync_no]
        @inbounds partial_pulse_len = sync_indices[partial_sync_no + 1] -
            sync_indices[partial_sync_no]
        shutter_closed_frac = closed_samples / partial_pulse_len

        # if shutter_closed_frac < 0.5, then the shutter probably opened during
        # the first frame that looks "open"
        fully_exposed_frame = exposed_edge_no + dark_search_dir *
            (shutter_closed_frac < 0.5)
    else
        @show exposed_edge_no, dark_edge_no
        error("What happened?")
    end

    return fully_exposed_frame, partial_sync_no + dark_search_direction
end

function sync_exposed_video_daq(
    syncdata,
    shutterdata,
    image_intensities,
    exposed_thresh,
    dark_thresh;
    skip_shutters = 0
)
    n_sync_samples = length(syncdata)
    sync_indices = find_sync_edges(syncdata)
    shutter_open_periods = find_shutter_edges(shutterdata)
    exposed_frame_periods, exposed_sync_periods = find_exposed_periods(
        sync_indices,
        shutter_open_periods,
        image_intensities,
        n_sync_samples,
        exposed_thresh,
        dark_thresh,
        skip_shutters = skip_shutters
    )
    sync_indices, exposed_frame_periods, exposed_sync_periods
end

function align_feather_files(
    vidfile,
    viddir = pwd(),
    roi::AbstractVector{<:UnitRange{<:Integer}} = UnitRange{Int}[],
    exposed_thresh = nothing,
    dark_thresh = nothing;
    skip_shutters = 0,
    thresh_stds = 3.0
) where S<:AbstractString
    vidpath = joinpath(viddir, vidfile)
    isfile(vidpath) || error("Could not find video file at $vidpath")

    m = match(FEATHER_VIDEO_REG, vidfile)
    m == nothing && throw(ArgumentError("Invalid video file $vidfile"))
    viddt = DateTime(m[1]::SubString{String}, FEATHER_DTF)

    daqpath = joinpath(viddir, make_feather_daqname(viddt))
    isfile(daqpath) || error("Could not find daq file at $daqpath")
    tspath = joinpath(viddir, make_feather_timestampsname(viddt))
    isfile(tspath) || error("Could not find time stamp file at $tspath")

    intensities = frame_intensities(vidpath, roi)
    if exposed_thresh == nothing || dark_thresh == nothing
        exposed_threshs, dark_thresh =
            two_gaussian_thresholds(intensities, thresh_stds)
    end

    micdata, syncdata, shutterdata = read_feather_video_daq_file(daqpath)
    sync_indices, exposed_frame_periods, exposed_sync_periods =
        sync_exposed_video_daq(
            syncdata,
            shutterdata,
            intensities,
            exposed_thresh,
            dark_thresh,
            skip_shutters = skip_shutters,
        )

    return sync_indices, exposed_frame_periods, exposed_sync_periods
end

align_feather_files(dir::AbstractString) =
    align_feather_files(joindir.(dir, readdir(dir)))
