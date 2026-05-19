' source/syncplay/SyncPlayTimeSync.brs

' ===========================================
' SyncPlay Time Synchronization
' NTP-style weighted-mean offset calculation
' for synchronized playback across clients
' ===========================================

' Constants
const SYNCPLAY_TIMESYNC_SAMPLE_COUNT = 5
const SYNCPLAY_MAX_ACCEPTABLE_RTT = 1000
const SYNCPLAY_STABILITY_VARIANCE_THRESHOLD = 50

function SyncPlayTimeSync() as Object
    obj = {
        ' Offset samples: array of {offset: Integer, rtt: Integer, timestamp: Float}
        offsetSamples: []

        ' Last sync timestamp (local time in ms)
        lastSyncTimestamp: 0#

        ' Drift correction factor
        driftRate: 1.0#

        ' Current computed offset in milliseconds
        ' (add to local time to get server time)
        offset: 0

        ' Estimated one-way latency in milliseconds
        latency: 0

        ' Initialize or restore from serialized state
        ' @param state Object - Optional serialized state
        init: function(state = invalid as Object)
            if state <> invalid and state.offsetSamples <> invalid then
                m.offsetSamples = state.offsetSamples
                m.driftRate = state.driftRate
                m.lastSyncTimestamp = state.lastSync
                m.recalculate()
            end if
        end function

        ' Get current time in milliseconds
        ' @return Integer - Unix timestamp in milliseconds
        getTimeMillis: function() as Integer
            dt = CreateObject("roDateTime")
            return dt.AsSeconds() * 1000 + dt.GetMilliseconds()
        end function

        ' Request a time sync ping to the server
        ' Returns the payload to send with local timestamp
        ' @return Object - Ping payload with client_time
        requestPing: function() as Object
            t1 = m.getTimeMillis()
            m.lastSyncTimestamp = t1
            return {
                type: "ping"
                client_time: t1
            }
        end function

        ' Process a pong response from server
        ' Calculates offset, RTT, latency and updates rolling average
        ' @param serverTime Integer - Server timestamp when pong was sent
        ' @param serverReceiveTime Integer - When server received our ping
        ' @param clientReceiveTime Integer - When we received the pong (defaults to now)
        ' @return Object - Time sync result {offset, latency, rtt, is_stable}
        processPong: function(serverTime as Integer, serverReceiveTime as Integer, clientReceiveTime = 0 as Integer) as Object
            if clientReceiveTime = 0 then
                clientReceiveTime = m.getTimeMillis()
            end if

            ' We need the original client_time we sent - we stored it in lastSyncTimestamp
            ' But we don't have access to it directly in this simplified version
            ' In practice the SyncPlayService manages the full exchange
            ' Here we calculate based on server timestamps only

            ' For the offset calculation, we need the original client send time
            ' Since we don't track it per-sample, we use the lastSyncTimestamp as approximation
            clientSendTime = m.lastSyncTimestamp

            ' Calculate round-trip time
            ' RTT = client_receive - client_send - (server_receive - server_time)
            rtt = clientReceiveTime - clientSendTime - (serverReceiveTime - serverTime)

            ' One-way latency estimate
            oneWayLatency = rtt / 2

            ' Calculate time offset
            ' offset = server_time - client_send_time + latency
            calculatedOffset = serverTime - clientSendTime + oneWayLatency

            ' Only accept samples with acceptable RTT
            if rtt <= SYNCPLAY_MAX_ACCEPTABLE_RTT then
                m.addSample(calculatedOffset, rtt)
            end if

            return m.getResult()
        end function

        ' Process pong from server with full payload
        ' @param payload Object - Pong payload {client_time, server_time, server_receive_time}
        ' @return Object - Time sync result
        processPongPayload: function(payload as Object) as Object
            clientSendTime = m.intVal(payload.client_time)
            serverTime = m.intVal(payload.server_time)
            serverReceiveTime = m.intVal(payload.server_receive_time)
            clientReceiveTime = m.getTimeMillis()

            rtt = clientReceiveTime - clientSendTime - (serverReceiveTime - serverTime)
            oneWayLatency = rtt / 2
            calculatedOffset = serverTime - clientSendTime + oneWayLatency

            if rtt <= SYNCPLAY_MAX_ACCEPTABLE_RTT then
                m.addSample(calculatedOffset, rtt)
            end if

            return m.getResult()
        end function

        ' Add an offset sample to the rolling collection
        ' @param offset Integer - Calculated time offset in ms
        ' @param rtt Integer - Round-trip time in ms
        addSample: function(offset as Integer, rtt as Integer)
            sample = {
                offset: offset
                rtt: rtt
                timestamp: m.getTimeMillis() / 1000.0#
            }

            m.offsetSamples.push(sample)

            ' Keep only recent samples (rolling buffer of 2x max)
            if m.offsetSamples.count() > SYNCPLAY_TIMESYNC_SAMPLE_COUNT * 2 then
                m.offsetSamples.shift()
            end if

            m.recalculate()
        end function

        ' Recalculate offset, latency from current samples
        recalculate: sub()
            if m.offsetSamples.count() = 0 then
                m.offset = 0
                m.latency = 0
                return
            end if

            ' Get last N samples
            recent = m.getRecentSamples()

            ' Calculate weighted average (favor lower RTT)
            weightedSum = 0#
            weightSum = 0#

            for each sample in recent
                weight = 1.0# / max(1, sample.rtt)
                weightedSum = weightedSum + (sample.offset * weight)
                weightSum = weightSum + weight
            next

            if weightSum > 0 then
                m.offset = int(weightedSum / weightSum)
            else
                m.offset = 0
            end if

            ' Calculate average latency
            totalLatency = 0
            for each sample in recent
                totalLatency = totalLatency + (sample.rtt / 2)
            next
            m.latency = int(totalLatency / max(1, recent.count()))
        end sub

        ' Get the most recent N samples
        ' @return Array - Recent offset samples
        getRecentSamples: function() as Object
            count = m.offsetSamples.count()
            if count <= SYNCPLAY_TIMESYNC_SAMPLE_COUNT then
                return m.offsetSamples
            end if
            return m.offsetSamples.slice(count - SYNCPLAY_TIMESYNC_SAMPLE_COUNT)
        end function

        ' Get the current time offset
        ' @return Integer - Offset in milliseconds
        getOffset: function() as Integer
            return m.offset
        end function

        ' Get estimated one-way latency
        ' @return Integer - Latency in milliseconds
        getLatency: function() as Integer
            return m.latency
        end function

        ' Get the estimated synchronized time
        ' @return Integer - Synchronized timestamp in ms
        getSynchronizedTime: function() as Integer
            return m.getTimeMillis() + m.offset
        end function

        ' Convert local timestamp to synchronized timestamp
        ' @param localTime Integer - Local timestamp in ms
        ' @return Integer - Synchronized timestamp in ms
        localToSynchronized: function(localTime as Integer) as Integer
            return localTime + m.offset
        end function

        ' Convert synchronized timestamp to local time
        ' @param syncTime Integer - Synchronized timestamp in ms
        ' @return Integer - Local timestamp in ms
        synchronizedToLocal: function(syncTime as Integer) as Integer
            return syncTime - m.offset
        end function

        ' Check if time sync is stable
        ' Stable when we have enough samples with low variance
        ' @return Boolean
        isStable: function() as Boolean
            if m.offsetSamples.count() < SYNCPLAY_TIMESYNC_SAMPLE_COUNT then
                return false
            end if

            recent = m.getRecentSamples()
            offsets = []
            for each sample in recent
                offsets.push(sample.offset)
            end for

            mean = m.arrayAvg(offsets)
            variance = m.arrayVariance(offsets, mean)

            return variance < SYNCPLAY_STABILITY_VARIANCE_THRESHOLD
        end function

        ' Calculate array average
        ' @param arr Array - Numeric array
        ' @return Float - Average value
        arrayAvg: function(arr as Object) as Float
            if arr.count() = 0 then return 0#
            sum = 0#
            for each val in arr
                sum = sum + val
            end for
            return sum / arr.count()
        end function

        ' Calculate array variance
        ' @param arr Array - Numeric array
        ' @param mean Float - Mean value
        ' @return Float - Variance
        arrayVariance: function(arr as Object, mean as Float) as Float
            if arr.count() = 0 then return 0#
            sumSquares = 0#
            for each val in arr
                diff = val - mean
                sumSquares = sumSquares + (diff * diff)
            next
            return sumSquares / arr.count()
        end function

        ' Get the drift rate
        ' @return Float - Drift rate multiplier (1.0 = no drift)
        getDriftRate: function() as Float
            return m.driftRate
        end function

        ' Apply drift correction to a predicted position
        ' @param targetTime Integer - Target synchronized time in ms
        ' @param currentTime Integer - Current local time in ms
        ' @return Integer - Corrected target time
        applyDriftCorrection: function(targetTime as Integer, currentTime as Integer) as Integer
            timeDelta = targetTime - currentTime
            return int(targetTime + (timeDelta * (1.0# - m.driftRate)))
        end function

        ' Reset time sync state
        reset: sub()
            m.offsetSamples = []
            m.offset = 0
            m.latency = 0
            m.driftRate = 1.0#
            m.lastSyncTimestamp = 0#
        end sub

        ' Get time sync status
        ' @return Object - Status info
        getStatus: function() as Object
            return {
                offset: m.offset
                latency: m.latency
                drift_rate: m.driftRate
                is_stable: m.isStable()
                sample_count: m.offsetSamples.count()
                last_sync: m.lastSyncTimestamp
            }
        end function

        ' Serialize state for persistence
        ' @return Object - Serialized state
        serialize: function() as Object
            return {
                offset_samples: m.offsetSamples
                drift_rate: m.driftRate
                last_sync: m.lastSyncTimestamp
            }
        end function

        ' Get time sync result object
        ' @return Object - Current sync result
        getResult: function() as Object
            return {
                offset: m.offset
                latency: m.latency
                rtt: m.latency * 2
                is_stable: m.isStable()
            }
        end function

        ' Safely get integer value from mixed
        ' @param val Dynamic - Value to convert
        ' @return Integer - Integer value
        intVal: function(val) as Integer
            if Type(val) = "Integer" then return val
            if Type(val) = "Float" then return int(val)
            if Type(val) = "String" then
                if IsValid(StrToI(val)) then return StrToI(val)
            end if
            return 0
        end function
    }

    return obj
end function

' Factory function
function SyncPlayTimeSyncFactory(state = invalid as Object) as Object
    ts = SyncPlayTimeSync()
    ts.init(state)
    return ts
end function