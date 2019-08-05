function open_avi(f, vidname, args...; kwargs...)
    io = VideoIO.open(vidname)
    try
        vidf = openvideo(io)
        try
            f(vidf, args...; kwargs...)
        finally
            close(vidf)
        end
    finally
        close(io)
    end
end

mean_intensity(img) = mean(Gray.(img)).val::Float64

function frame_intensities(vidname::AbstractString, roi = UnitRange{Int}[])
    open_avi(vidname) do vidf
        intensities = Float64[]
        eof(vidf) && return intensities
        img = read(vidf)
        if isempty(roi)
            nv, nh = size(img)
            roi = [UnitRange(1, nv), UnitRange(1, nh)]
        elseif length(roi) != 2
            error("roi must be empty or length two")
        end
        push!(intensities, mean_intensity(view(img, roi[1], roi[2])))
        while !eof(vidf)
            read!(vidf, img)
            push!(intensities, mean_intensity(view(img, roi[1], roi[2])))
        end
        return intensities
    end
end

function count_frames(vidname)
    open_avi(vidname) do vidf
        if eof(vidf)
            return 0
        else
            nframe = 1
            img = read(vidf)
            while !eof(vidf)
                nframe += 1
                read!(vidf, img)
            end
            return nframe
        end
    end
end

# Returns width x height or nothing
function avi_frame_size(vidname)
    open_avi(vidname) do vidf
        if eof(vidf)
            return nothing
        else
            img = read(vidf)
            height, width = size(img)
        end
        return width, height
    end
end

function read_avi(vidname::AbstractString)
    nframes = count_frames(vidname)
    nframes == 0 && return nothing
    open_avi(vidname) do vidf
        img = read(vidf)
        nv, nh = size(img)
        grayimg = Gray.(img)
        imgs = similar(grayimg, nv, nh, nframes)
        imgs[:, :, 1] = grayimg
        frameno = 2
        while !eof(vidf)
            read!(vidf, img)
            imgs[:, :, frameno] = Gray.(img)
            frameno += 1
        end
        return imgs
    end
end

function crop_clip_video(
    vidfile,
    viddir,
    outdir,
    roi,
    exposed_periods,
    framerate;
    force = false
)
    isdir(outdir) || throw(ArgumentError("Output directory $outdir does not exist"))
    inputpath = joinpath(viddir, vidfile)
    isfile(inputpath) || throw(ArugmentError("Input video $inputpath does not exist"))

    nsplit = size(exposed_periods, 2)
    viddt = feather_file_dt(vidfile)
    dt_str = make_feather_dt_str(viddt)

    offsets = (exposed_periods[1, :] .- 1) ./ framerate
    durations = (exposed_periods[2, :] .- exposed_periods[1, :] .+ 1) ./ framerate

    roi_topleft = first.(roi)
    roi_spans = length.(roi)

    roi_str = "$(roi_spans[2]):$(roi_spans[1]):$(roi_topleft[2]):$(roi_topleft[1])"
    vidsize_str = "$(roi_spans[2])x$(roi_spans[1])"

    newfiles = Vector{String}(undef, nsplit)
    for splitno in 1:nsplit
        offset_str = @sprintf "%.3f" offsets[splitno]
        dur_str = @sprintf "%.3f" durations[splitno]
        offset_file_str = replace(offset_str, '.' => 's')

        outfile = format(viddt, FEATHER_DTF) * "_video_offset_" * offset_file_str * ".avi"
        outpath = joinpath(outdir, outfile)
        if isfile(outpath)
            if force
                rm(outpath)
            else
                error("Video $outpath already exists, set 'force = true' to overwrite")
            end
        end

        run(
              `
                ffmpeg
                -i $inputpath
                -ss $(offset_str)
                -t $(dur_str)
                -filter:v
                "crop=$(roi_str)"
                -c:v rawvideo
                -pixel_format pal8
                -framerate $framerate
                -video_size $(vidsize_str)
                $(outpath)
              `
        )
        newfiles[splitno] = outpath
    end
    newfiles
end
