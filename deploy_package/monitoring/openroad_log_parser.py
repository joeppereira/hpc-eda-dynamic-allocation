#!/usr/bin/env python3
"""
OpenROAD log parser - Detects stages and extracts design features from logs
"""

import re
from datetime import datetime
from typing import Dict, List, Optional
from dataclasses import dataclass
from enum import Enum


class Stage(Enum):
    """OpenROAD execution stages"""
    READ_DESIGN = "read_design"
    FLOORPLAN = "floorplan"
    PLACEMENT = "placement"
    CTS = "cts"
    ROUTING = "routing"
    FINISHING = "finishing"


@dataclass
class StageEvent:
    """Stage transition event"""
    stage: Stage
    event_type: str  # 'start' or 'end'
    timestamp: datetime
    line_number: int
    message: str


@dataclass
class DesignFeatures:
    """Extracted design features"""
    cell_count: Optional[int] = None
    net_count: Optional[int] = None
    die_area_um2: Optional[float] = None
    utilization: Optional[float] = None
    clock_freq_mhz: Optional[float] = None
    technology_node: Optional[str] = None


class OpenROADLogParser:
    """Parser for OpenROAD log files"""
    
    # Stage detection patterns
    STAGE_PATTERNS = {
        Stage.READ_DESIGN: {
            'start': [
                r'\[INFO\]\s+Reading\s+LEF',
                r'\[INFO\]\s+Reading\s+DEF',
                r'\[INFO\]\s+Reading\s+Liberty',
            ],
            'end': [
                r'\[INFO\].*design\s+read\s+complete',
            ]
        },
        Stage.FLOORPLAN: {
            'start': [
                r'\[INFO\]\s+initialize_floorplan',
                r'\[INFO\].*Starting\s+floorplan',
            ],
            'end': [
                r'\[INFO\].*Floorplan\s+complete',
                r'\[INFO\].*floorplan\s+finished',
            ]
        },
        Stage.PLACEMENT: {
            'start': [
                r'\[INFO\]\s+Starting\s+global\s+placement',
                r'\[INFO\].*global_placement',
            ],
            'end': [
                r'\[INFO\]\s+Global\s+placement\s+complete',
                r'\[INFO\]\s+Detailed\s+placement\s+complete',
            ]
        },
        Stage.CTS: {
            'start': [
                r'\[INFO\]\s+Starting\s+clock\s+tree',
                r'\[INFO\].*clock_tree_synthesis',
            ],
            'end': [
                r'\[INFO\].*Clock\s+tree\s+synthesis\s+complete',
                r'\[INFO\].*CTS\s+complete',
            ]
        },
        Stage.ROUTING: {
            'start': [
                r'\[INFO\]\s+Starting\s+global\s+routing',
                r'\[INFO\].*global_route',
            ],
            'end': [
                r'\[INFO\]\s+Detailed\s+routing\s+complete',
                r'\[INFO\].*routing\s+finished',
            ]
        },
        Stage.FINISHING: {
            'start': [
                r'\[INFO\]\s+Writing\s+DEF',
                r'\[INFO\]\s+Writing\s+GDS',
            ],
            'end': [
                r'\[INFO\].*write\s+complete',
            ]
        }
    }
    
    # Design feature extraction patterns
    FEATURE_PATTERNS = {
        'cell_count': [
            r'Number\s+of\s+instances:\s+(\d+)',
            r'Total\s+cells:\s+(\d+)',
            r'Instance\s+count:\s+(\d+)',
        ],
        'net_count': [
            r'Number\s+of\s+nets:\s+(\d+)',
            r'Total\s+nets:\s+(\d+)',
        ],
        'die_area': [
            r'Design\s+area\s+(\d+\.?\d*)\s+u\^2',
            r'Die\s+area:\s+(\d+\.?\d*)',
        ],
        'utilization': [
            r'Utilization:\s+([\d.]+)',
            r'Core\s+utilization:\s+([\d.]+)%?',
        ],
        'clock_period': [
            r'create_clock.*-period\s+([\d.]+)',
            r'Clock\s+period:\s+([\d.]+)',
        ],
    }
    
    def __init__(self):
        self.stage_events: List[StageEvent] = []
        self.design_features = DesignFeatures()
        self.current_stage: Optional[Stage] = None
        self.line_number = 0
        
        # Compile regex patterns for efficiency
        self.compiled_patterns = {}
        for stage, patterns in self.STAGE_PATTERNS.items():
            self.compiled_patterns[stage] = {
                'start': [re.compile(p, re.IGNORECASE) for p in patterns['start']],
                'end': [re.compile(p, re.IGNORECASE) for p in patterns['end']]
            }
        
        self.compiled_features = {}
        for feature, patterns in self.FEATURE_PATTERNS.items():
            self.compiled_features[feature] = [re.compile(p, re.IGNORECASE) for p in patterns]
    
    def parse_line(self, line: str, timestamp: Optional[datetime] = None) -> Optional[StageEvent]:
        """
        Parse a single log line
        
        Args:
            line: Log line to parse
            timestamp: Optional timestamp (extracted from log or current time)
            
        Returns:
            StageEvent if stage transition detected, None otherwise
        """
        self.line_number += 1
        
        if timestamp is None:
            timestamp = datetime.now()
        
        # Check for stage transitions
        for stage, patterns in self.compiled_patterns.items():
            # Check for stage start
            for pattern in patterns['start']:
                if pattern.search(line):
                    event = StageEvent(
                        stage=stage,
                        event_type='start',
                        timestamp=timestamp,
                        line_number=self.line_number,
                        message=line.strip()
                    )
                    self.stage_events.append(event)
                    self.current_stage = stage
                    return event
            
            # Check for stage end
            for pattern in patterns['end']:
                if pattern.search(line):
                    event = StageEvent(
                        stage=stage,
                        event_type='end',
                        timestamp=timestamp,
                        line_number=self.line_number,
                        message=line.strip()
                    )
                    self.stage_events.append(event)
                    if self.current_stage == stage:
                        self.current_stage = None
                    return event
        
        # Extract design features
        self._extract_features(line)
        
        return None
    
    def _extract_features(self, line: str):
        """Extract design features from log line"""
        
        # Cell count
        if self.design_features.cell_count is None:
            for pattern in self.compiled_features['cell_count']:
                match = pattern.search(line)
                if match:
                    self.design_features.cell_count = int(match.group(1))
                    break
        
        # Net count
        if self.design_features.net_count is None:
            for pattern in self.compiled_features['net_count']:
                match = pattern.search(line)
                if match:
                    self.design_features.net_count = int(match.group(1))
                    break
        
        # Die area
        if self.design_features.die_area_um2 is None:
            for pattern in self.compiled_features['die_area']:
                match = pattern.search(line)
                if match:
                    self.design_features.die_area_um2 = float(match.group(1))
                    break
        
        # Utilization
        if self.design_features.utilization is None:
            for pattern in self.compiled_features['utilization']:
                match = pattern.search(line)
                if match:
                    util = float(match.group(1))
                    # Convert to 0-1 range if given as percentage
                    if util > 1.0:
                        util = util / 100.0
                    self.design_features.utilization = util
                    break
        
        # Clock frequency (from period)
        if self.design_features.clock_freq_mhz is None:
            for pattern in self.compiled_features['clock_period']:
                match = pattern.search(line)
                if match:
                    period_ns = float(match.group(1))
                    # Convert period (ns) to frequency (MHz)
                    self.design_features.clock_freq_mhz = 1000.0 / period_ns
                    break
    
    def parse_file(self, log_file_path: str) -> Dict:
        """
        Parse entire log file
        
        Args:
            log_file_path: Path to OpenROAD log file
            
        Returns:
            Dictionary with stage events and design features
        """
        with open(log_file_path, 'r') as f:
            for line in f:
                # Try to extract timestamp from log line
                timestamp = self._extract_timestamp(line)
                self.parse_line(line, timestamp)
        
        return self.get_results()
    
    def _extract_timestamp(self, line: str) -> Optional[datetime]:
        """Extract timestamp from log line if present"""
        # Common log timestamp patterns
        patterns = [
            r'\[(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\]',
            r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})',
        ]
        
        for pattern in patterns:
            match = re.search(pattern, line)
            if match:
                try:
                    ts_str = match.group(1)
                    # Try different formats
                    for fmt in ['%Y-%m-%d %H:%M:%S', '%Y-%m-%dT%H:%M:%S']:
                        try:
                            return datetime.strptime(ts_str, fmt)
                        except ValueError:
                            continue
                except:
                    pass
        
        return None
    
    def get_results(self) -> Dict:
        """Get parsing results"""
        return {
            'stage_events': [
                {
                    'stage': event.stage.value,
                    'event_type': event.event_type,
                    'timestamp': event.timestamp.isoformat(),
                    'line_number': event.line_number,
                    'message': event.message
                }
                for event in self.stage_events
            ],
            'design_features': {
                'cell_count': self.design_features.cell_count,
                'net_count': self.design_features.net_count,
                'die_area_um2': self.design_features.die_area_um2,
                'utilization': self.design_features.utilization,
                'clock_freq_mhz': self.design_features.clock_freq_mhz,
                'technology_node': self.design_features.technology_node,
            },
            'total_stages_detected': len(set(e.stage for e in self.stage_events)),
            'total_events': len(self.stage_events)
        }
    
    def get_stage_durations(self) -> Dict[str, float]:
        """Calculate duration for each stage"""
        durations = {}
        stage_starts = {}
        
        for event in self.stage_events:
            stage_name = event.stage.value
            
            if event.event_type == 'start':
                stage_starts[stage_name] = event.timestamp
            elif event.event_type == 'end' and stage_name in stage_starts:
                duration = (event.timestamp - stage_starts[stage_name]).total_seconds()
                durations[stage_name] = duration
                del stage_starts[stage_name]
        
        return durations


if __name__ == "__main__":
    import sys
    import json
    
    if len(sys.argv) < 2:
        print("Usage: python openroad_log_parser.py <log_file>")
        sys.exit(1)
    
    log_file = sys.argv[1]
    
    parser = OpenROADLogParser()
    results = parser.parse_file(log_file)
    
    print(json.dumps(results, indent=2))
    
    print("\nStage Durations:")
    durations = parser.get_stage_durations()
    for stage, duration in durations.items():
        print(f"  {stage}: {duration:.2f} seconds")
