using FeatherScope, Dates

using FeatherScope: FEATHER_VIDEO_REG

datadir = "/home/glynch/Documents/Data/gcamp/7221/2019-04-03"
datafiles = joinpath.(datadir, readdir(datadir))
framerate = 30

analysisdir = "/home/glynch/Documents/Analysis/gcamp/7221/2019-04-03"
vidlistfile = "selected_videos.csv"
vidlistpath = joinpath(analysisdir, vidlistfile)
files_to_analyze = readlines(vidlistpath)
nok = length(files_to_analyze)
vid_dts = feather_file_dt.(files_to_analyze)
vidpaths = joinpath.(datadir, files_to_analyze)
daq_files = joinpath.(datadir, make_feather_daqname.(vid_dts))

exposed_thresh = 0.5
dark_thresh = 0.036

roi = [62:361, 255:554]
intensities = map(f -> frame_intensities(f, roi), vidpaths)

vidlens = length.(intensities)
ok_intensities = vcat(intensities[1:3], intensities[5:13], intensities[15:end])
ok_vidlens = length.(ok_intensities)
ok_viddurs = ok_vidlens ./ framerate

time_between_vids = diff(vid_starttimes)
s_between_vids = map(x -> x.value / 1000, time_between_vids)
overlap_mask = s_between_vids .<= ok_viddurs[1:(end-1)]

sync_indices = Vector{Vector{Int}}(undef, nok)
exposed_frame_periods = similar(sync_indices, Matrix{Int})
exposed_sync_periods = similar(exposed_frame_periods)
for i = 1:nok
    @show i
    sync_indices[i], exposed_frame_periods[i], exposed_sync_periods[i] =
        align_feather_files(files_to_analyze[i], datadir, roi, exposed_thresh, dark_thresh)

end

syncpath = joinpath(analysisdir, "videosync.csv")

open(syncpath, "w") do io
    for i = 1:nok
        println(
            io,
            join(
                [
                    files_to_analyze[i],
                    repr(sync_indices[i]),
                    repr(exposed_frame_periods[i]),
                    repr(exposed_sync_periods[i]),
                ],
                '|',
            ),
        )
    end
end

split_vids = Vector{Vector{String}}(undef, nok)
for vidno = 1:nok
    split_vids[vidno] = crop_clip_video(
        files_to_analyze[vidno],
        datadir,
        analysisdir,
        roi,
        exposed_frame_periods[vidno],
        framerate,
        force = true,
    )
end
