import UIKit
import Stockee
import Combine

class KLineChartViewController: UIViewController {
    // MARK: - Properties
    private var cancellables = Set<AnyCancellable>()
    
    // ViewModel
    private let viewModel: KLineChartViewModel
    
    // UI Components
    private let periodSelector: UISegmentedControl
    private let priceInfoLabel: UILabel
    private let chartContainerView: UIView
    private let timelineLabel: UILabel
    
    // Stockee Chart
    private var stockeeChartView: Stockee.ChartView?
    
    // MARK: - Initialization
    init(viewModel: KLineChartViewModel) {
        self.viewModel = viewModel
        
        // Initialize UI components
        let periodTitles = TimePeriod.allCases.map { $0.rawValue }
        periodSelector = UISegmentedControl(items: periodTitles)
        priceInfoLabel = UILabel()
        chartContainerView = UIView()
        timelineLabel = UILabel()
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupConstraints()
        setupBindings()
        setupPeriodSelector()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Period Selector
        periodSelector.selectedSegmentIndex = TimePeriod.allCases.firstIndex(of: viewModel.interval) ?? 0
        periodSelector.addTarget(self, action: #selector(periodChanged(_:)), for: .valueChanged)
        view.addSubview(periodSelector)
        
        // Price Info Label
        priceInfoLabel.font = .systemFont(ofSize: 16, weight: .medium)
        priceInfoLabel.textColor = .label
        view.addSubview(priceInfoLabel)
        
        // Chart Container
        chartContainerView.backgroundColor = .systemBackground
        view.addSubview(chartContainerView)
        
        // Timeline Label
        timelineLabel.font = .systemFont(ofSize: 12, weight: .light)
        timelineLabel.textColor = .secondaryLabel
        timelineLabel.textAlignment = .center
        view.addSubview(timelineLabel)
        
        // Initialize Stockee Chart
        setupStockeeChart()
    }
    
    private func setupConstraints() {
        // Enable Auto Layout
        [periodSelector, priceInfoLabel, chartContainerView, timelineLabel].forEach { 
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        // Constraints
        NSLayoutConstraint.activate([
            // Period Selector
            periodSelector.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            periodSelector.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            periodSelector.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Price Info Label
            priceInfoLabel.topAnchor.constraint(equalTo: periodSelector.bottomAnchor, constant: 16),
            priceInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            priceInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Chart Container
            chartContainerView.topAnchor.constraint(equalTo: priceInfoLabel.bottomAnchor, constant: 16),
            chartContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            chartContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            chartContainerView.heightAnchor.constraint(equalToConstant: 330),
            
            // Timeline Label
            timelineLabel.topAnchor.constraint(equalTo: chartContainerView.bottomAnchor, constant: 8),
            timelineLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            timelineLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            timelineLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    private func setupBindings() {
        // Observe data changes
        viewModel.$originalData
            .receive(on: DispatchQueue.main)
            .sink {
                [weak self] data in
                self?.updateChart(with: data)
                self?.updatePriceInfo(with: data)
                self?.updateTimeline(with: data)
            }
            .store(in: &cancellables)
        
        // Observe interval changes
        viewModel.$interval
            .receive(on: DispatchQueue.main)
            .sink {
                [weak self] interval in
                guard let self = self else { return }
                let index = TimePeriod.allCases.firstIndex(of: interval) ?? 0
                self.periodSelector.selectedSegmentIndex = index
            }
            .store(in: &cancellables)
    }
    
    private func setupPeriodSelector() {
        // Set initial selection
        let initialIndex = TimePeriod.allCases.firstIndex(of: viewModel.interval) ?? 0
        periodSelector.selectedSegmentIndex = initialIndex
    }
    
    private func setupStockeeChart() {
        // Create Stockee Chart Configuration
        let configuration = Stockee.ChartConfiguration(
            theme: .light,
            chartType: .candlestick,
            showVolume: true,
            volumeChartHeight: 80,
            mainChartHeight: 250
        )
        
        // Create Stockee Chart View
        stockeeChartView = Stockee.ChartView(configuration: configuration)
        
        // Add chart to container
        if let chartView = stockeeChartView {
            chartContainerView.addSubview(chartView)
            chartView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                chartView.topAnchor.constraint(equalTo: chartContainerView.topAnchor),
                chartView.leadingAnchor.constraint(equalTo: chartContainerView.leadingAnchor),
                chartView.trailingAnchor.constraint(equalTo: chartContainerView.trailingAnchor),
                chartView.bottomAnchor.constraint(equalTo: chartContainerView.bottomAnchor)
            ])
        }
    }
    
    // MARK: - Updates
    private func updateChart(with data: [CandleStickData]) {
        // Convert data to Stockee format
        let stockeeData = data.map { candle -> Stockee.CandlestickData in
            return Stockee.CandlestickData(
                date: candle.timestamp,
                open: candle.open.asDouble,
                high: candle.high.asDouble,
                low: candle.low.asDouble,
                close: candle.close.asDouble,
                volume: candle.volumes.asDouble
            )
        }
        
        // Update Stockee Chart
        stockeeChartView?.setData(stockeeData, animated: true)
    }
    
    private func updatePriceInfo(with data: [CandleStickData]) {
        guard let lastCandle = data.last else {
            priceInfoLabel.text = "No data available"
            return
        }
        
        let changePercentage = calculateChangePercentage(data: data)
        let priceInfo = String(format: "当前价: %.2f | 涨跌幅: %.2f%%", lastCandle.close.asDouble, changePercentage)
        priceInfoLabel.text = priceInfo
    }
    
    private func updateTimeline(with data: [CandleStickData]) {
        guard !data.isEmpty else {
            timelineLabel.text = ""
            return
        }
        
        let firstDate = data.first?.timestamp ?? Date()
        let lastDate = data.last?.timestamp ?? Date()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd"
        
        let timelineText = "\(dateFormatter.string(from: firstDate)) - \(dateFormatter.string(from: lastDate))"
        timelineLabel.text = timelineText
    }
    
    // MARK: - Helper Methods
    private func calculateChangePercentage(data: [CandleStickData]) -> Double {
        guard let first = data.first, let last = data.last else {
            return 0.0
        }
        
        let change = ((last.close - first.open) / first.open) * 100
        return change.asDouble
    }
    
    // MARK: - Actions
    @objc private func periodChanged(_ sender: UISegmentedControl) {
        guard sender.selectedSegmentIndex < TimePeriod.allCases.count else { return }
        
        let selectedPeriod = TimePeriod.allCases[sender.selectedSegmentIndex]
        viewModel.interval = selectedPeriod
    }
}
