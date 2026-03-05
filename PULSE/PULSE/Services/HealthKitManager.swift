import Foundation
import HealthKit

class HealthKitManager {
    private let store = HKHealthStore()

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        // Mobility & fitness
        HKObjectType.quantityType(forIdentifier: .vo2Max)!,
        HKObjectType.quantityType(forIdentifier: .heartRateRecoveryOneMinute)!,
        HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)!,
        HKObjectType.quantityType(forIdentifier: .walkingSpeed)!,
        HKObjectType.quantityType(forIdentifier: .stairAscentSpeed)!,
        HKObjectType.quantityType(forIdentifier: .stairDescentSpeed)!
    ]

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw AppError.healthKitUnavailable
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            throw AppError.healthKitAuthorizationDenied
        }
    }

    // MARK: - Today's Summary

    func fetchTodaySummary() async throws -> HealthSummary {
        let today = Date()
        async let hrv = fetchHRV()
        async let restingHR = fetchRestingHR()
        async let sleep = fetchSleep()
        async let respRate = fetchRespiratoryRate()
        async let calories = fetchActiveCalories()
        async let steps = fetchSteps()
        async let todayCal = fetchTodayActiveCalories()
        async let todaySteps = fetchTodaySteps()
        async let vo2Max = fetchVO2Max()
        async let cardioRecovery = fetchCardioRecovery()
        async let walkingHR = fetchWalkingHeartRateAverage()
        async let walkingSpeed = fetchWalkingSpeed()
        async let stairUp = fetchStairAscentSpeed()
        async let stairDown = fetchStairDescentSpeed()

        let (hrvVal, rhrVal, sleepResult, respVal, calVal, stepsVal, todayCalVal, todayStepsVal,
             vo2MaxVal, cardioRecoveryVal, walkingHRVal, walkingSpeedVal, stairUpVal, stairDownVal) =
            try await (hrv, restingHR, sleep, respRate, calories, steps, todayCal, todaySteps,
                       vo2Max, cardioRecovery, walkingHR, walkingSpeed, stairUp, stairDown)

        return HealthSummary(
            date: today,
            hrv: hrvVal,
            restingHR: rhrVal,
            sleepHours: sleepResult?.hours,
            sleepEfficiency: sleepResult?.efficiency,
            respiratoryRate: respVal,
            activeCalories: calVal,
            steps: stepsVal,
            wakeTime: sleepResult?.wakeTime,
            todayCalories: todayCalVal,
            todaySteps: todayStepsVal,
            vo2Max: vo2MaxVal,
            cardioRecovery: cardioRecoveryVal,
            walkingHeartRate: walkingHRVal,
            walkingSpeed: walkingSpeedVal,
            stairAscentSpeed: stairUpVal,
            stairDescentSpeed: stairDownVal
        )
    }

    // MARK: - HRV

    /// Average SDNN samples from the previous night's sleep window (9pm–9am).
    private func fetchHRV() async throws -> Double? {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let start = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: yesterday()) ?? yesterday()
        let end = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        let samples = try await fetchQuantitySamples(type: type, start: start, end: end)
        guard !samples.isEmpty else { return nil }
        let values = samples.map { $0.quantity.doubleValue(for: .init(from: "ms")) }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Resting HR

    private func fetchRestingHR() async throws -> Double? {
        let type = HKQuantityType(.restingHeartRate)
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        let samples = try await fetchQuantitySamples(type: type, start: start, end: end)
        return samples.last?.quantity.doubleValue(for: HKUnit(from: "count/min"))
    }

    // MARK: - Sleep

    private struct SleepResult {
        let hours: Double
        let efficiency: Double
        let wakeTime: Date
    }

    private func fetchSleep() async throws -> SleepResult? {
        let type = HKCategoryType(.sleepAnalysis)
        let start = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday()) ?? yesterday()
        let end = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()

        let samples = try await fetchCategorySamples(type: type, start: start, end: end)

        let asleepStages: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        let asleepSamples = samples.filter { asleepStages.contains($0.value) }
        guard !asleepSamples.isEmpty else { return nil }

        let totalAsleep = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let earliestStart = samples.map(\.startDate).min() ?? start
        let latestEnd = samples.map(\.endDate).max() ?? end
        let timeInBed = latestEnd.timeIntervalSince(earliestStart)

        let hours = totalAsleep / 3600
        let efficiency = timeInBed > 0 ? totalAsleep / timeInBed : 0

        return SleepResult(hours: hours, efficiency: min(efficiency, 1.0), wakeTime: latestEnd)
    }

    // MARK: - Respiratory Rate

    private func fetchRespiratoryRate() async throws -> Double? {
        let type = HKQuantityType(.respiratoryRate)
        let start = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: yesterday()) ?? yesterday()
        let end = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        let samples = try await fetchQuantitySamples(type: type, start: start, end: end)
        guard !samples.isEmpty else { return nil }
        let values = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Active Calories

    private func fetchActiveCalories() async throws -> Double? {
        let type = HKQuantityType(.activeEnergyBurned)
        let start = Calendar.current.startOfDay(for: yesterday())
        let end = Calendar.current.startOfDay(for: Date())
        return try await fetchSum(type: type, unit: .kilocalorie(), start: start, end: end)
    }

    // MARK: - Steps

    private func fetchSteps() async throws -> Int? {
        let type = HKQuantityType(.stepCount)
        let start = Calendar.current.startOfDay(for: yesterday())
        let end = Calendar.current.startOfDay(for: Date())
        guard let sum = try await fetchSum(type: type, unit: .count(), start: start, end: end) else {
            return nil
        }
        return Int(sum)
    }

    // MARK: - Today's Real-Time Activity

    /// Active calories burned from midnight today until now.
    private func fetchTodayActiveCalories() async throws -> Double? {
        let type = HKQuantityType(.activeEnergyBurned)
        let start = Calendar.current.startOfDay(for: Date())
        return try await fetchSum(type: type, unit: .kilocalorie(), start: start, end: Date())
    }

    /// Steps taken from midnight today until now.
    private func fetchTodaySteps() async throws -> Int? {
        let type = HKQuantityType(.stepCount)
        let start = Calendar.current.startOfDay(for: Date())
        guard let sum = try await fetchSum(type: type, unit: .count(), start: start, end: Date()) else {
            return nil
        }
        return Int(sum)
    }

    // MARK: - Mobility & Fitness

    /// VO2 max — most recent Apple Watch estimate from the last 90 days.
    private func fetchVO2Max() async throws -> Double? {
        let type = HKQuantityType(.vo2Max)
        let start = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))
        let samples = try await fetchQuantitySamples(type: type, start: start, end: Date())
        return samples.last?.quantity.doubleValue(for: unit)
    }

    /// Heart rate recovery at 1 min post-exercise — most recent Watch measurement from last 30 days.
    private func fetchCardioRecovery() async throws -> Double? {
        let type = HKQuantityType(.heartRateRecoveryOneMinute)
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let samples = try await fetchQuantitySamples(type: type, start: start, end: Date())
        return samples.last?.quantity.doubleValue(for: HKUnit(from: "count/min"))
    }

    /// Average walking heart rate from yesterday (Apple Watch — uses walkingHeartRateAverage identifier).
    private func fetchWalkingHeartRateAverage() async throws -> Double? {
        let type = HKQuantityType(.walkingHeartRateAverage)
        let start = Calendar.current.startOfDay(for: yesterday())
        let end = Calendar.current.startOfDay(for: Date())
        let samples = try await fetchQuantitySamples(type: type, start: start, end: end)
        guard !samples.isEmpty else { return nil }
        let values = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 7-day rolling average of iPhone-measured walking speed (m/s).
    private func fetchWalkingSpeed() async throws -> Double? {
        let type = HKQuantityType(.walkingSpeed)
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let unit = HKUnit.meter().unitDivided(by: HKUnit.second())
        let samples = try await fetchQuantitySamples(type: type, start: start, end: Date())
        guard !samples.isEmpty else { return nil }
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 7-day rolling average of iPhone-measured stair ascent speed (m/s).
    private func fetchStairAscentSpeed() async throws -> Double? {
        let type = HKQuantityType(.stairAscentSpeed)
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let unit = HKUnit.meter().unitDivided(by: HKUnit.second())
        let samples = try await fetchQuantitySamples(type: type, start: start, end: Date())
        guard !samples.isEmpty else { return nil }
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 7-day rolling average of iPhone-measured stair descent speed (m/s).
    private func fetchStairDescentSpeed() async throws -> Double? {
        let type = HKQuantityType(.stairDescentSpeed)
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let unit = HKUnit.meter().unitDivided(by: HKUnit.second())
        let samples = try await fetchQuantitySamples(type: type, start: start, end: Date())
        guard !samples.isEmpty else { return nil }
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Generic Query Helpers

    private func fetchQuantitySamples(
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: AppError.healthKitQueryFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    private func fetchCategorySamples(
        type: HKCategoryType,
        start: Date,
        end: Date
    ) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: AppError.healthKitQueryFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    private func fetchSum(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: AppError.healthKitQueryFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Helpers

    private func yesterday() -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }
}
