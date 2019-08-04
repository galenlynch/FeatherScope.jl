const FEATHER_FRAME_gm = 0xC0
const FEATHER_FRAME_gc = 0x40
const FEATHER_INPUT_gm = 0x20
const FEATHER_SYNC_gm = 0x0C
const FEATHER_LV_gm = 0x08
const FEATHER_FV_gm = 0x04
const FEATHER_HIGHBITS_gm = 0x03

struct FeatherAdcChannelResults
    sampnos::Vector{Int}
    reads::Vector{UInt16}
    fv::BitVector
    lv::BitVector
end

function load_featherscope_adc_reads(datfile, header_skip = 81, ncheck = 10)
    data = open(mmap, datfile, "r")
    ndata = length(data)
    ndata > header_skip + 2 * (ncheck + 1) || error("Not enough data to check")
    if check_featherdat_offset(data, header_skip, ncheck)
        data_start = header_skip + 1
    elseif check_featherdat_offset(data, header_skip + 1, ncheck)
        data_start = header_skip + 2
    else
        error("Could not find frame starts")
    end

    ainch8_res = Vector{FeatherAdcChannelResults}()
    ainch9_res = Vector{FeatherAdcChannelResults}()
    sampnos_8 = Vector{Int}()
    sampnos_9 = similar(sampnos_8)
    reads_8 = Vector{UInt16}()
    reads_9 = similar(reads_8)
    fv_8 = BitVector()
    fv_9 = similar(fv_8)
    lv_8 = similar(fv_8)
    lv_9 = similar(lv_8)

    # First two bytes are ok because we just checked them
    adc_read, ain9, fv, lv = unpack_adc_read(
        data[data_start], data[data_start + 1]
    )::Tuple{UInt16, Bool, Bool, Bool}
    if ain9
        push!(sampnos_9, 1)
        push!(reads_9, adc_read)
        push!(fv_9, fv)
        push!(lv_9, lv)
    else
        push!(sampnos_8, 1)
        push!(reads_8, adc_read)
        push!(fv_8, fv)
        push!(lv_8, lv)
    end
    last_ain9 = ain9
    sampno = 2
    bytepos = data_start + 2
    while bytepos < ndata - 1
        maybe_read = unpack_adc_read(data[bytepos], data[bytepos + 1])
        if maybe_read == nothing
            # Something is wrong with the data
            if bytepos + ncheck  + 3 < ndata
                # Done
                break
            else
                if !isempty(sampnos_8)
                    push!(
                        ainch8_res,
                        FeatherAdcChannelResults(sampnos_8, reads_8, fv_8, lv_8)
                    )
                end
                if !isempty(sampnos_9)
                    push!(
                        ainch9_res,
                        FeatherAdcChannelResults(sampnos_9, reads_9, fv_9, lv_9)
                    )
                end
                if check_featherdat_offset(data, bytepos + 3, ncheck)
                    bytepos += 3
                elseif check_featherdat_offset(data, bytepos + 2, ncheck)
                    bytepos += 2
                else
                    @warn "Could not find a good alignment"
                    break
                end
                # Check for alignment
            end
        else
            adc_read, ain9, fv, lv = maybe_read::Tuple{UInt16, Bool, Bool, Bool}
            last_ain9 = ain9
            if ain9
                push!(sampnos_9, 1)
                push!(reads_9, adc_read)
                push!(fv_9, fv)
                push!(lv_9, lv)
            else
                push!(sampnos_8, 1)
                push!(reads_8, adc_read)
                push!(fv_8, fv)
                push!(lv_8, lv)
            end
            bytepos += 2
        end
        sampno += 1
    end
    if !isempty(sampnos_8)
        push!(
            ainch8_res,
            FeatherAdcChannelResults(sampnos_8, reads_8, fv_8, lv_8)
        )
    end
    if !isempty(sampnos_9)
        push!(
            ainch9_res,
            FeatherAdcChannelResults(sampnos_9, reads_9, fv_9, lv_9)
        )
    end
    return ainch8_res, ainch9_res
end

check_highbyte(bhigh) = bhigh & FEATHER_FRAME_gm == FEATHER_FRAME_gc

function check_featherdat_offset(data, startposition, ncheck)
    ok = true
    checkno = 0
    while ok && checkno < ncheck
        ok = check_highbyte(data[startposition + 2 * (checkno)])
        checkno += 1
    end
    ok
end

check_bit(byte::T, mask::T) where T = (byte & mask) != zero(T)

function unpack_adc_read(blow, bhigh)
    check_highbyte(bhigh) || return nothing
    adc_read = convert(UInt16, blow)
    adc_read |= convert(UInt16, bhigh & FEATHER_HIGHBITS_gm) << 8
    ain9 = check_bit(bhigh, FEATHER_INPUT_gm)
    fv = check_bit(bhigh, FEATHER_FV_gm)
    lv = check_bit(bhigh, FEATHER_LV_gm)
    return adc_read, ain9, fv, lv
end

